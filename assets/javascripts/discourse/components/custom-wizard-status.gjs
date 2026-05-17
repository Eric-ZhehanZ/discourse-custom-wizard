import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DiscourseURL from "discourse/lib/url";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dLoadingSpinner from "discourse/ui-kit/helpers/d-loading-spinner";
import { i18n } from "discourse-i18n";
import {
  findCustomWizard,
  updateCachedWizard,
} from "../models/custom-wizard";

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
  // Earlier attempts kept a tracked reference to the whole wizard
  // EmberObject and read sub-properties off it in getters. Glimmer
  // only invalidates a getter when one of its tracked dependencies
  // changes, and an EmberObject property is not a tracked
  // dependency — so when refresh swapped in a new wizard with the
  // same shape, only the small slice that read `this.<tracked>`
  // directly re-rendered (the secondary link), and title/body kept
  // their stale values. Tracking each rendered slice as its own
  // primitive @tracked field guarantees Glimmer sees a real change
  // and re-renders every consumer.
  @tracked _state;
  @tracked _previouslyApproved;
  @tracked _rejectionReason;
  @tracked _canDeactivate;
  @tracked _destinationUrl;

  constructor() {
    super(...arguments);
    this._syncFromWizard(this.args.wizard);
  }

  _syncFromWizard(w) {
    this._state = w?.review_state || "none";
    this._previouslyApproved = !!w?.previously_approved;
    this._rejectionReason = w?.rejection_reason || null;
    this._canDeactivate = !!w?.can_deactivate;
    this._destinationUrl = w?.redirect_back_url || "/";
  }

  get state() {
    return this._state;
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
    return this._previouslyApproved;
  }
  get isPendingFirstTime() {
    return this.isPending && !this.previouslyApproved;
  }
  get rejectionReason() {
    return this._rejectionReason;
  }
  get canDeactivate() {
    return this._canDeactivate;
  }
  get destinationUrl() {
    return this._destinationUrl;
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
  primary(event) {
    event?.preventDefault?.();
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
  secondary(event) {
    // The link element renders with an empty href so it picks up
    // Discourse's action-link styling; preventing default stops the
    // browser from "navigating" to the same URL (which would look
    // like an unnecessary hard refresh on top of our SPA action).
    event?.preventDefault?.();
    if (this.isApproved) {
      this._openWizardForm();
      return;
    }
    if (this.isPending) {
      this._refreshStatus();
      return;
    }
    if (this.isDenied && this.canDeactivate) {
      this._deactivate();
    }
  }

  // Pull fresh wizard JSON, copy each rendered slice to its tracked
  // field (guarantees re-render), mutate args.wizard so sibling
  // components also see the new state, and update the shared wizard
  // cache so subsequent route loads start clean.
  async _refreshStatus() {
    if (this.submitting) return;
    this.submitting = true;
    try {
      const fresh = await findCustomWizard(this.args.wizardId);
      this._syncFromWizard(fresh);
      if (this.args.wizard?.setProperties) {
        this.args.wizard.setProperties({
          review_state: fresh.review_state,
          pending_review: fresh.pending_review,
          previously_approved: fresh.previously_approved,
          must_redo: fresh.must_redo,
          rejection_reason: fresh.rejection_reason,
          redirect_back_url: fresh.redirect_back_url,
          can_deactivate: fresh.can_deactivate,
        });
      }
      updateCachedWizard(fresh);
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.submitting = false;
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
        {{! Mirror the wizard step's loading affordance: while a refresh
            or deactivation ajax call is in flight, swap the buttons for
            the same spinner the Next button shows. }}
        {{#if this.submitting}}
          {{dLoadingSpinner size="small"}}
        {{else}}
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
              {{on "click" this.primary}}
            >
              {{i18n this.primaryLabelKey}}
              {{dIcon "chevron-right"}}
            </button>
          {{/if}}
        {{/if}}
      </div>
    </div>
  </template>
}
