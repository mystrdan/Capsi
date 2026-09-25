import { CAPSI_CONFIG } from "../config.js";

const apply = url => document.querySelectorAll("a.js-download").forEach(link => link.setAttribute("href", url));

export function initDownloads() {
  apply(CAPSI_CONFIG.DOWNLOAD_URL);
}