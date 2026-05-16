import Component from "@glimmer/component";
import avatar from "discourse/helpers/avatar";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

// Returns the i18n string for `key` if present, otherwise `fallback`.
function maybeI18n(key, fallback) {
  const value = i18n(key);
  return value === key ? fallback : value;
}

export default class ReviewableCustomWizardSubmission extends Component {
  get wizardName() {
    return (
      this.args.reviewable?.wizard_name ||
      this.args.reviewable?.wizard_id ||
      i18n("admin.wizard.review.unnamed_wizard")
    );
  }

  get wizardUrl() {
    const id = this.args.reviewable?.wizard_id;
    return id ? `/w/${id}` : null;
  }

  get user() {
    return this.args.reviewable?.submission_user;
  }

  get fields() {
    return this.args.reviewable?.enriched_fields || [];
  }

  get actions() {
    return (this.args.reviewable?.enriched_actions || []).map((a) => {
      const type = a.type || "";
      const label =
        a.label ||
        maybeI18n(`admin.wizard.action.${type}.label`, type) ||
        type;
      return { id: a.id, type, label };
    });
  }

  <template>
    <div class="review-item__meta-content custom-wizard-submission-review">
      <h3 class="wizard-name">
        {{i18n "admin.wizard.review.wizard_label"}}
        {{#if this.wizardUrl}}
          <a
            href={{this.wizardUrl}}
            target="_blank"
            rel="noopener noreferrer"
          >{{this.wizardName}}</a>
        {{else}}
          {{this.wizardName}}
        {{/if}}
      </h3>

      {{#if this.user}}
        <div class="wizard-submission-user">
          <a
            class="avatar"
            href={{this.user.profile_url}}
            target="_blank"
            rel="noopener noreferrer"
          >
            {{avatar this.user imageSize="medium"}}
          </a>
          <div class="user-details">
            <div class="user-line username">
              <a
                href={{this.user.profile_url}}
                target="_blank"
                rel="noopener noreferrer"
              >@{{this.user.username}}</a>
              {{#if this.user.admin_url}}
                · <a
                  href={{this.user.admin_url}}
                  target="_blank"
                  rel="noopener noreferrer"
                >{{i18n "admin.wizard.review.admin_link"}}</a>
              {{/if}}
            </div>
            {{#if this.user.name}}
              <div class="user-line name">{{this.user.name}}</div>
            {{/if}}
            {{#if this.user.email}}
              <div class="user-line email">{{this.user.email}}</div>
            {{/if}}
          </div>
        </div>
      {{/if}}

      {{#if this.actions.length}}
        <div class="wizard-pending-actions">
          <h4>{{i18n "admin.wizard.review.actions_heading"}}</h4>
          <ul class="action-list">
            {{#each this.actions as |action|}}
              <li>{{action.label}}</li>
            {{/each}}
          </ul>
        </div>
      {{/if}}

      {{#if this.fields.length}}
        <div class="wizard-submission-fields">
          <h4>{{i18n "admin.wizard.review.fields_heading"}}</h4>
          <table class="wizard-submission-table">
            <thead>
              <tr>
                <th>{{i18n "admin.wizard.review.column_field"}}</th>
                <th>{{i18n "admin.wizard.review.column_value"}}</th>
              </tr>
            </thead>
            <tbody>
              {{#each this.fields as |field|}}
                <tr>
                  <td class="field-label">{{field.label}}</td>
                  <td class="field-value">
                    {{#if (eq field.type "upload")}}
                      <a
                        class="wizard-upload-link"
                        href={{field.upload.url}}
                        target="_blank"
                        rel="noopener noreferrer"
                      >{{field.upload.filename}}</a>
                    {{else}}
                      {{field.value}}
                    {{/if}}
                  </td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{/if}}
    </div>
  </template>
}
