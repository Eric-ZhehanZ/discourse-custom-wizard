import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";

export default class ReviewableCustomWizardSubmission extends Component {
  get wizardName() {
    return (
      this.args.reviewable?.wizard_name ||
      this.args.reviewable?.payload?.wizard_name ||
      this.args.reviewable?.wizard_id ||
      i18n("admin.wizard.review.unnamed_wizard")
    );
  }

  get wizardUrl() {
    const id = this.args.reviewable?.wizard_id || this.args.reviewable?.payload?.wizard_id;
    return id ? `/w/${id}` : null;
  }

  get actions() {
    return this.args.reviewable?.payload?.actions || [];
  }

  get fields() {
    const f = this.args.reviewable?.payload?.submission_fields || {};
    // Hide internal meta keys: route_to, redirect_*, submitted_at, ...
    const skip = new Set([
      "id",
      "route_to",
      "redirect_on_complete",
      "redirect_to",
      "submitted_at",
      "updated_at",
      "permitted_param_keys",
    ]);
    return Object.entries(f)
      .filter(([k]) => !skip.has(k))
      .map(([k, v]) => ({ key: k, value: this.#stringify(v) }));
  }

  #stringify(value) {
    if (value == null) {
      return "";
    }
    if (typeof value === "object") {
      try {
        return JSON.stringify(value);
      } catch {
        return String(value);
      }
    }
    return String(value);
  }

  <template>
    <div class="review-item__meta-content custom-wizard-submission-review">
      <h3 class="wizard-name">
        {{i18n "admin.wizard.review.wizard_label"}}
        {{#if this.wizardUrl}}
          <a href={{this.wizardUrl}} target="_blank" rel="noopener">{{this.wizardName}}</a>
        {{else}}
          {{this.wizardName}}
        {{/if}}
      </h3>

      {{#if this.actions.length}}
        <div class="wizard-pending-actions">
          <h4>{{i18n "admin.wizard.review.actions_heading"}}</h4>
          <ul>
            {{#each this.actions as |action|}}
              <li>
                <strong>{{action.type}}</strong>
                {{#if action.id}}
                  <code class="action-id">{{action.id}}</code>
                {{/if}}
              </li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

      {{#if this.fields.length}}
        <div class="wizard-submission-fields">
          <h4>{{i18n "admin.wizard.review.fields_heading"}}</h4>
          <dl>
            {{#each this.fields as |field|}}
              <dt>{{field.key}}</dt>
              <dd>{{field.value}}</dd>
            {{/each}}
          </dl>
        </div>
      {{/if}}
    </div>
  </template>
}
