//! Length-prefixed framing for Capsi's TCP connections.
//!
//! A connection carries a stream of sealed frames, so each one is preceded by its
//! length. The length is applied to the *sealed* bytes, which means a peer cannot
//! make us allocate memory for a huge frame by lying inside the ciphertext: the
//! ceiling is enforced before any decryption is attempted.

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::crypto::FRAME_OVERHEAD;
use crate::error::{CapsiError, Result};

/// Hard ceiling for a single frame.
///
/// A 256 KiB transfer chunk becomes ~350 KiB once base64-encoded and sealed, so
/// this leaves generous headroom while still being far below anything that would
/// trouble a desktop machine.
pub const MAX_FRAME_BYTES: usize = 16 * 1024 * 1024;

/// Write one framed blob: `length (4, big-endian) || bytes`.
pub async fn write_frame<W>(writer: &mut W, bytes: &[u8]) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    if bytes.len() > MAX_FRAME_BYTES {
        return Err(CapsiError::Protocol(format!(
            "frame of {} bytes exceeds the {} byte limit",
            bytes.len(),
            MAX_FRAME_BYTES
        )));
    }
    writer.write_all(&(bytes.len() as u32).to_be_bytes()).await?;
    writer.write_all(bytes).await?;
    writer.flush().await?;
    Ok(())
}

/// Read one framed blob, or `None` when the peer closed the connection cleanly.
pub async fn read_frame<R>(reader: &mut R) -> Result<Option<Vec<u8>>>
where
    R: AsyncRead + Unpin,
{
    let mut length = [0u8; 4];
    match reader.read_exact(&mut length).await {
        Ok(_) => {}
        // A clean EOF between frames is how peers say goodbye.
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(CapsiError::Network(e.to_string())),
    }
    let length = u32::from_be_bytes(length) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(CapsiError::Protocol(format!(
            "peer announced a {length} byte frame (limit {MAX_FRAME_BYTES})"
        )));
    }
    // A frame always carries at least a counter and a Poly1305 tag.
    if length < FRAME_OVERHEAD {
        return Err(CapsiError::Protocol(format!(
            "peer announced an impossibly short frame ({length} bytes)"
        )));
    }
    let mut buffer = vec![0u8; length];
    reader
        .read_exact(&mut buffer)
        .await
        .map_err(|e| CapsiError::Network(format!("truncated frame: {e}")))?;
    Ok(Some(buffer))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn frames_round_trip() {
        let (mut client, mut server) = tokio::io::duplex(64 * 1024);
        // Realistic sealed frames: a counter, a payload and a Poly1305 tag.
        let payload = vec![7u8; 1024];
        let sent = payload.clone();
        let second = vec![9u8; 64];
        let sent_second = second.clone();
        tokio::spawn(async move {
            write_frame(&mut client, &sent).await.unwrap();
            // A second frame must come back in order.
            write_frame(&mut client, &sent_second).await.unwrap();
        });

        let first = read_frame(&mut server).await.unwrap().unwrap();
        assert_eq!(first, payload);
        let returned = read_frame(&mut server).await.unwrap().unwrap();
        assert_eq!(returned, second);
    }

    #[tokio::test]
    async fn a_zero_length_frame_is_refused() {
        let (mut client, mut server) = tokio::io::duplex(1024);
        client.write_all(&0u32.to_be_bytes()).await.unwrap();
        assert!(read_frame(&mut server).await.is_err());
    }

    #[tokio::test]
    async fn a_clean_eof_reports_none() {
        let (client, mut server) = tokio::io::duplex(1024);
        drop(client);
        assert!(read_frame(&mut server).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn an_oversized_frame_is_refused_before_allocating() {
        let (mut client, mut server) = tokio::io::duplex(1024);
        // Announce 64 MiB and send nothing: the reader must refuse immediately.
        client
            .write_all(&(64u32 * 1024 * 1024).to_be_bytes())
            .await
            .unwrap();
        let err = read_frame(&mut server).await.unwrap_err().to_string();
        assert!(err.contains("exceeds the 16 MiB limit") || err.contains("announced"), "{err}");
    }

    #[tokio::test]
    async fn an_impossibly_short_frame_is_refused() {
        let (mut client, mut server) = tokio::io::duplex(1024);
        client.write_all(&(8u32).to_be_bytes()).await.unwrap();
        client.write_all(&[0u8; 8]).await.unwrap();
        assert!(read_frame(&mut server).await.is_err());
    }

    #[tokio::test]
    async fn writing_a_frame_larger_than_the_ceiling_fails() {
        let (mut client, _server) = tokio::io::duplex(1024);
        let huge = vec![0u8; MAX_FRAME_BYTES + 1];
        assert!(write_frame(&mut client, &huge).await.is_err());
    }

    #[tokio::test]
    async fn a_truncated_frame_is_reported() {
        let (mut client, mut server) = tokio::io::duplex(1024);
        client.write_all(&(64u32).to_be_bytes()).await.unwrap();
        client.write_all(&[1u8; 10]).await.unwrap();
        drop(client);
        let err = read_frame(&mut server).await.unwrap_err().to_string();
        assert!(err.contains("truncated"), "{err}");
    }
}