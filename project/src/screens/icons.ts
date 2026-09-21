import { createElement } from "lucide";

export type IconNode = Parameters<typeof createElement>[0];

const ICON_SIZE = 20;

export function createIcon(iconNode: IconNode, size: number = ICON_SIZE): SVGElement {
  return createElement(iconNode, { width: size, height: size, "aria-hidden": "true", focusable: "false" });
}

export function setIconButton(button: HTMLButtonElement, iconNode: IconNode, label: string, size?: number): void {
  button.replaceChildren(createIcon(iconNode, size));
  button.title = label;
  button.setAttribute("aria-label", label);
}
