import { escapeHtml } from "./graph.mjs";

function inline(value) {
  let text = escapeHtml(value);
  text = text.replace(/`([^`]+)`/g, "<code>$1</code>");
  text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  return text.replace(
    /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
    '<a href="$2" rel="noopener noreferrer" target="_blank">$1</a>',
  );
}

export function renderMarkdown(value) {
  const lines = String(value ?? "")
    .replace(/\r/g, "")
    .split("\n");
  const blocks = [];
  let paragraph = [];
  let list = null;
  const flushParagraph = () => {
    if (paragraph.length) blocks.push(`<p>${inline(paragraph.join(" "))}</p>`);
    paragraph = [];
  };
  const flushList = () => {
    if (list)
      blocks.push(
        `<${list.tag}>${list.items.map((item) => `<li>${inline(item)}</li>`).join("")}</${list.tag}>`,
      );
    list = null;
  };
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line.startsWith("```")) {
      flushParagraph();
      flushList();
      const code = [];
      while (++index < lines.length && !lines[index].startsWith("```"))
        code.push(lines[index]);
      blocks.push(`<pre><code>${escapeHtml(code.join("\n"))}</code></pre>`);
    } else if (!line.trim()) {
      flushParagraph();
      flushList();
    } else {
      const match = line.match(/^(?:([-*])|(\d+)\.)\s+(.+)$/);
      if (match) {
        flushParagraph();
        const tag = match[2] ? "ol" : "ul";
        if (!list || list.tag !== tag) {
          flushList();
          list = { tag, items: [] };
        }
        list.items.push(match[3]);
      } else {
        flushList();
        paragraph.push(line);
      }
    }
  }
  flushParagraph();
  flushList();
  return blocks.join("");
}
