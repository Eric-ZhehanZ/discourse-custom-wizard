import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// User-facing wizard status page. Uses the exact same DOM structure as
// custom-wizard-step.hbs so it inherits the wizard's existing layout
// (title position, content block, divider + footer with right-aligned
// buttons). No bespoke styling.
//
// State matrix:
//   approved              → "Continue" / "Update my information again"
//   pending, first-time   → no primary / "Refresh status"
//   pending, re-verify    → "Continue to site" / "Refresh status"
//   denied                → "Resubmit" / "Give up and deactivate"
export default class CustomWizardStatus extends Component {
  @service router;
  @tracked submitting = false;

  get state() {
    return this.args.wizard?.review_state || "none";
  }
  get isApproved() {
    return this.state === "approved";
  }
  get isPending() {
    return this.state === "pending";
  }
  get isDenied() {
    return this.state === "denied";
  }
  get previouslyApproved() {
    return !!this.args.wizard?.previously_approved;
  }
  get isPendingFirstTime() {
    return this.isPending && !this.previouslyApproved;
  }
  get rejectionReason() {
    return this.args.wizard?.rejection_reason;
  }
  get canDeactivate() {
    return !!this.args.wizard?.can_deactivate;
  }
  get destinationUrl() {
    return this.args.wizard?.redirect_back_url || "/";
  }

  get titleKey() {
    if (this.isApproved) return "wizard.status.approved.title";
    if (this.isDenied) return "wizard.status.denied.title";
    if (this.isPendingFirstTime) return "wizard.status.pending_first.title";
    return "wizard.status.pending_update.title";
  }
  get bodyKey() {
    if (this.isApproved) return "wizard.status.approved.body";
    if (this.isDenied) return "wizard.status.denied.body";
    if (this.isPendingFirstTime) return "wizard.status.pending_first.body";
    return "wizard.status.pending_update.body";
  }
  get primaryLabelKey() {
    if (this.isApproved) return "wizard.status.approved.primary";
    if (this.isDenied) return "wizard.status.denied.primary";
    if (this.isPending && !this.isPendingFirstTime)
      return "wizard.status.pending_update.primary";
    return null;
  }
  get secondaryLabelKey() {
    if (this.isApproved) return "wizard.status.approved.secondary";
    if (this.isDenied && this.canDeactivate)
      return "wizard.status.denied.secondary";
    if (this.isPending) return "wizard.status.pending.refresh";
    return null;
  }
  get secondaryIsDangerous() {
    return this.isDenied;
  }

  @action
  primary() {
    if (this.isApproved || (this.isPending && !this.isPendingFirstTime)) {
      // Use Discourse's URL router so internal destinations transition
      // via Ember instead of triggering a full page reload.
      DiscourseURL.routeTo(this.destinationUrl);
      return;
    }
    if (this.isDenied) {
      this._openWizardForm();
    }
  }

  @action
  secondary() {
    if (this.isApproved) {
      this._openWizardForm();
      return;
    }
    if (this.isPending) {
      // Re-fetch the wizard via the route's model hook instead of a
      // full window reload.
      this.router.refresh();
      return;
    }
    if (this.isDenied && this.canDeactivate) {
      this._deactivate();
    }
  }

  _openWizardForm() {
    const start = this.args.wizard?.start;
    if (start) {
      this.router.transitionTo("customWizardStep", start);
    }
  }

  async _deactivate() {
    if (this.submitting) return;
    if (!confirm(i18n("wizard.status.denied.deactivate_confirm"))) return;
    this.submitting = true;
    try {
      const data = await ajax(`/w/${this.args.wizardId}/deactivate`, {
        type: "POST",
      });
      window.location.href = data.redirect_to || "/";
    } catch (e) {
      this.submitting = false;
      popupAjaxError(e);
    }
  }

  <template>
    <div class="wizard-step-contents wizard-status-page">
      <h1 class="wizard-step-title">{{i18n this.titleKey}}</h1>
      <div class="wizard-step-description">{{i18n this.bodyKey}}</div>
      {{#if this.rejectionReason}}
        <div class="wizard-step-description wizard-status__reason">
          {{this.rejectionReason}}
        </div>
      {{/if}}
    </div>

    <div class="wizard-step-footer">
      <div class="wizard-buttons">
        {{#if this.secondaryLabelKey}}
          <a
            href
            role="button"
            class="action-link{{if
                this.secondaryIsDangerous
                ' wizard-status__danger'
              }}"
            {{on "click" this.secondary}}
          >{{i18n this.secondaryLabelKey}}</a>
        {{/if}}

        {{#if this.primaryLabelKey}}
          <button
            type="button"
            class="wizard-btn next primary"
            disabled={{this.submitting}}
            {{on "click" this.primary}}
          >
            {{i18n this.primaryLabelKey}}
            {{dIcon "chevron-right"}}
          </button>
        {{/if}}
      </div>
    </div>
  </template>
}
