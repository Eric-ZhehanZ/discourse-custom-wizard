import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";
import { trustHTML } from "@ember/template";

// Lightweight cross-controller state for the active wizard step and
// background uploads.
//
// `activeStep` / `activeWizard` are set by `custom-wizard-step` so the
// parent template can render the progress bar next to the site logo.
//
// `pendingUploads` tracks in-flight uploads across ALL fields in the
// wizard — set from `custom-wizard-field-upload` via
// `registerUpload` / `releaseUpload`. The rule (per design):
//
//   - Start upload on select
//   - Track uploads globally
//   - DO NOT block step advances if the mandatory upload field has a file
//     selected (even if it's still uploading in the background)
//   - DO block final submission (the Done button) until ALL uploads are
//     complete, so no field ends up with a null value at submit time.
export default class WizardStateService extends Service {
  @tracked activeStep = null;
  @tracked activeWizard = null;
  @tracked pendingUploads = 0;

  // Promises created by `whenIdle()` while uploads are in-flight. Each one
  // is resolved the moment `pendingUploads` drops back to zero.
  #idleWaiters = [];

  setActive(wizard, step) {
    this.activeWizard = wizard;
    this.activeStep = step;
  }

  clear() {
    this.activeWizard = null;
    this.activeStep = null;
  }

  registerUpload() {
    this.pendingUploads = this.pendingUploads + 1;
  }

  releaseUpload() {
    const next = this.pendingUploads - 1;
    this.pendingUploads = next < 0 ? 0 : next;
    if (this.pendingUploads === 0 && this.#idleWaiters.length) {
      const resolvers = this.#idleWaiters;
      this.#idleWaiters = [];
      resolvers.forEach((resolve) => resolve());
    }
  }

  resetUploads() {
    this.pendingUploads = 0;
    const resolvers = this.#idleWaiters;
    this.#idleWaiters = [];
    resolvers.forEach((resolve) => resolve());
  }

  // Returns a promise that resolves as soon as `pendingUploads` is 0. Used
  // by the step save flow: the user can click Next while an upload is
  // still running, and the step waits for the upload to finish before
  // sending field values to the server. Resolves immediately if there are
  // no uploads in flight.
  whenIdle() {
    if (this.pendingUploads === 0) {
      return Promise.resolve();
    }
    return new Promise((resolve) => this.#idleWaiters.push(resolve));
  }

  get hasPendingUploads() {
    return this.pendingUploads > 0;
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
