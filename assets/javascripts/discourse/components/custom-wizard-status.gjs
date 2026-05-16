import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

// Single user-facing status page for the wizard. Replaces the old
// noAccess "pending review" / "recently approved" screens with a
// four-state layout (approved / pending-first-time / pending-update /
// denied) that mirrors the wizard form's chrome (primary button in the
// same place as Next, secondary link where the progress bar sits).
//
// Args: @wizard, @wizardId, @routeTo
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

  // First-time pending (held): the user has never had an approved
  // submission for this wizard, so they're blocked from the rest of
  // the forum until this review lands.
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
    if (!this.isPendingFirstTime && this.isPending)
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

  @action
  primary() {
    if (this.isApproved || (this.isPending && !this.isPendingFirstTime)) {
      window.location.href = this.destinationUrl;
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
      window.location.reload();
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
    <div class="wizard-status wizard-status--{{this.state}}">
      <div class="wizard-status__content">
        <h1 class="wizard-status__title">{{i18n this.titleKey}}</h1>
        <p class="wizard-status__body">{{i18n this.bodyKey}}</p>
        {{#if (eq this.state "denied")}}
          {{#if this.rejectionReason}}
            <p class="wizard-status__reason">{{this.rejectionReason}}</p>
          {{/if}}
        {{/if}}

        {{#if this.primaryLabelKey}}
          <div class="wizard-status__primary">
            <button
              type="button"
              class="wizard-btn next primary"
              disabled={{this.submitting}}
              {{on "click" this.primary}}
            >
              {{i18n this.primaryLabelKey}}
              {{dIcon "chevron-right"}}
            </button>
          </div>
        {{/if}}
      </div>

      {{#if this.secondaryLabelKey}}
        <div class="wizard-status__secondary">
          <a
            role="button"
            class="wizard-status__secondary-link"
            {{on "click" this.secondary}}
          >{{i18n this.secondaryLabelKey}}</a>
        </div>
      {{/if}}
    </div>
  </template>
}
