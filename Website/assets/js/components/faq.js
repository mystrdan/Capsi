export function initFAQ() {
  const items = document.querySelectorAll(".faq-item");
  items.forEach(item => {
    const button = item.querySelector(".faq-question");
    const answer = item.querySelector(".faq-answer");
    if (!button || !answer) return;
    button.addEventListener("click", () => {
      const open = button.getAttribute("aria-expanded") === "true";
      items.forEach(other => {
        other.classList.remove("open");
        const otherButton = other.querySelector(".faq-question");
        const otherAnswer = other.querySelector(".faq-answer");
        if (otherButton) otherButton.setAttribute("aria-expanded", "false");
        if (otherAnswer) otherAnswer.classList.remove("open");
      });
      if (!open) {
        item.classList.add("open");
        button.setAttribute("aria-expanded", "true");
        answer.classList.add("open");
      }
    });
  });
}