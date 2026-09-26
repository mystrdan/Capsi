//! Direct TCP transport for the Capsi wire protocol.
//!
//! Platform-neutral: Windows, Android, iOS and macOS shells can use the same
//! signed handshake, framing and encrypted message path.

use tokio::net::TcpStream;

use crate::{
    crypto::{Handshake, Session},
    error::{CapsiError, Result},
    identity::{DeviceId, DeviceIdentity},
    protocol::{read_frame, write_frame, Envelope},
};

pub async fn connect_and_send(
    addr: &str,
    identity: &DeviceIdentity,
    expected_peer: &DeviceId,
    envelope: &Envelope,
) -> Result<()> {
    let mut stream = TcpStream::connect(addr)
        .await
        .map_err(|e| CapsiError::Network(format!("cannot connect to {addr}: {e}")))?;

    let mine = Handshake::create(identity)?;
    write_handshake(&mut stream, &mine).await?;
    let theirs = read_handshake(&mut stream).await?;

    if &theirs.device_id != expected_peer {
        return Err(CapsiError::Protocol(
            "peer identity does not match the discovered device".into(),
        ));
    }

    let mut session = Session::establish(identity, &mine, &theirs, true)?;
    let sealed = session.seal_json(envelope)?;
    write_frame(&mut stream, &sealed).await
}

pub async fn accept_and_read(
    mut stream: TcpStream,
    identity: &DeviceIdentity,
) -> Result<(DeviceId, Envelope)> {
    let theirs = read_handshake(&mut stream).await?;
    theirs.verify()?;

    let mine = Handshake::create(identity)?;
    write_handshake(&mut stream, &mine).await?;

    let peer = theirs.device_id.clone();
    let mut session = Session::establish(identity, &mine, &theirs, false)?;
    let frame = read_frame(&mut stream)
        .await?
        .ok_or_else(|| CapsiError::Network("peer closed before sending a message".into()))?;
    let json = session.open(&frame)?;
    let envelope = Envelope::from_json(&json)?;
    Ok((peer, envelope))
}

async fn write_handshake(stream: &mut TcpStream, handshake: &Handshake) -> Result<()> {
    let bytes = serde_json::to_vec(handshake)?;
    write_frame(stream, &bytes).await
}

async fn read_handshake(stream: &mut TcpStream) -> Result<Handshake> {
    let frame = read_frame(stream)
        .await?
        .ok_or_else(|| CapsiError::Network("peer closed during handshake".into()))?;
    serde_json::from_slice(&frame)
        .map_err(|e| CapsiError::Protocol(format!("invalid handshake: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn handshake_and_encrypted_message_round_trip() {
        let a = DeviceIdentity::from_secrets(&[1; 32], &[2; 32]);
        let b = DeviceIdentity::from_secrets(&[3; 32], &[4; 32]);
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let expected = b.id().clone();

        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            accept_and_read(stream, &b).await.unwrap()
        });

        let envelope = Envelope::new(crate::protocol::Message::Text(
            crate::protocol::TextMessage::new("hello").unwrap(),
        ));
        connect_and_send(&addr.to_string(), &a, &expected, &envelope)
            .await
            .unwrap();

        let (peer, received) = server.await.unwrap();
        assert_eq!(peer, a.id().clone());
        assert_eq!(received.message.kind(), "text");
    }
}
