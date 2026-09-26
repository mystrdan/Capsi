import { initNavigation } from "./components/navigation.js";
import { initDownloads } from "./components/download.js";
import { initFAQ } from "./components/faq.js";
import { renderHeader } from "./components/header.js";
import { renderFooter } from "./components/footer.js";

document.addEventListener("DOMContentLoaded", () => {
  renderHeader();
  renderFooter();
  initNavigation();
  initDownloads();
  initFAQ();
});