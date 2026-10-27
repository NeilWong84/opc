import { Popup, type PopupProps } from 'tdesign-vue-next';
import { uiScale } from '../composables/preferences';

interface PopupState {
  elements: { reference: Element; popper: HTMLElement };
  rects: { reference: { x: number; y: number; width: number; height: number } };
}

// Popper 2 rounds trigger dimensions when estimating scale. Its zero-height
// portal parent also loses the vertical scale after scrolling. Use the same
// exact document scale as our CSS, before Popper calculates placement/overflow.
export const scaledPopupProps: PopupProps = {
  popperOptions: {
    modifiers: [{
      name: 'opcDocumentScale',
      enabled: true,
      phase: 'beforeRead',
      fn({ state }: { state: PopupState }) {
        const scale = uiScale.value / 100;
        const parent = state.elements.popper.offsetParent;
        if (scale === 1 || !(parent instanceof HTMLElement)) return;
        const reference = state.elements.reference.getBoundingClientRect();
        const origin = parent.getBoundingClientRect();
        state.rects.reference = {
          x: (reference.left - origin.left) / scale + parent.scrollLeft - parent.clientLeft,
          y: (reference.top - origin.top) / scale + parent.scrollTop - parent.clientTop,
          width: reference.width / scale,
          height: reference.height / scale,
        };
      },
    }],
  },
};

export function initializeScaledPopups() {
  // TDesign 1.20.9's date panel creates its own month/year Select instances
  // without a public popupProps pass-through. Configure the Vue Popup prop
  // default before mounting so those nested popups use the same correction.
  // Keep this adapter covered by the nested-calendar browser regression when
  // upgrading TDesign. Explicit caller popperOptions still take precedence.
  const component = Popup as unknown as {
    props: { popperOptions: { default?: () => PopupProps['popperOptions'] } };
  };
  component.props.popperOptions.default = () => scaledPopupProps.popperOptions;
}
