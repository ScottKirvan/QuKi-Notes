import { createElement } from "lucide";

export type IconNode = Parameters<typeof createElement>[0];

const BUTTON_ICON_SIZE = 24;

export function createIcon(iconNode: IconNode, size: number): SVGElement {
  return createElement(iconNode, { width: size, height: size, "aria-hidden": "true", focusable: "false" });
}

export function setIconButton(button: HTMLButtonElement, iconNode: IconNode, label: string, size: number = BUTTON_ICON_SIZE): void {
  button.replaceChildren(createIcon(iconNode, size));
  button.title = label;
  button.setAttribute("aria-label", label);
}
