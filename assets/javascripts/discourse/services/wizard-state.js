import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";
import { trustHTML } from "@ember/template";

// Lightweight cross-controller state for the active wizard step.
//
// The `custom-wizard-step` component sets `activeStep` / `activeWizard` as
// soon as it receives attrs, and clears them on destroy. The parent
// `custom-wizard` template reads from this service to render the progress
// bar in the wizard footer (next to the site logo) — keeping the DOM
// structure clean while still reflecting the live step state.
export default class WizardStateService extends Service {
  @tracked activeStep = null;
  @tracked activeWizard = null;

  setActive(wizard, step) {
    this.activeWizard = wizard;
    this.activeStep = step;
  }

  clear() {
    this.activeWizard = null;
    this.activeStep = null;
  }

  get hasProgress() {
    return !!this.activeWizard && !!this.activeStep;
  }

  get totalSteps() {
    return this.activeWizard?.totalSteps || 0;
  }

  get displayIndex() {
    return this.activeStep?.displayIndex || 0;
  }

  // Matches the ratio math from the old `barStyle` computed on
  // custom-wizard-step — ratio is clamped to [0, 1] and scaled to the
  // pixel width of the bar (200px).
  get barStyle() {
    const total = parseFloat(this.totalSteps);
    const index = parseFloat(this.activeStep?.index || 0);
    let ratio = 0;
    if (total && total > 1) {
      ratio = index / (total - 1);
      if (ratio < 0) {
        ratio = 0;
      }
      if (ratio > 1) {
        ratio = 1;
      }
    }
    return trustHTML(`width: ${ratio * 200}px`);
  }
}
