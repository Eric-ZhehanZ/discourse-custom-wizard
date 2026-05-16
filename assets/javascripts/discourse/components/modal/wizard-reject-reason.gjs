import Component from "@glimmer/component";
import { Input, Textarea } from "@ember/component";
import { action } from "@ember/object";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

// A "reject with reason" modal patterned on Discourse's
// RejectReasonReviewableModal but without the post/user-delete labels
// (the built-in modal's confirm button says "Delete user", which is
// misleading for a wizard submission — we're not deleting anyone, we're
// asking the user to resubmit.)
export default class WizardRejectReasonModal extends Component {
  rejectReason;
  sendEmail = true;

  @action
  async perform() {
    this.args.model.reviewable.setProperties({
      rejectReason: this.rejectReason,
      sendEmail: this.sendEmail,
    });
    this.args.closeModal();
    await this.args.model.performConfirmed(this.args.model.action);
  }

  <template>
    <DModal
      @bodyClass="wizard-reject-reason-modal__body"
      @closeModal={{@closeModal}}
      @title={{i18n "admin.wizard.review.reject_modal.title"}}
      class="wizard-reject-reason-modal"
    >
      <:body>
        <p>{{i18n "admin.wizard.review.reject_modal.instructions"}}</p>
        <Textarea
          @value={{this.rejectReason}}
          placeholder={{i18n
            "admin.wizard.review.reject_modal.placeholder"
          }}
        />
        <div class="control-group">
          <label>
            <Input @type="checkbox" @checked={{this.sendEmail}} />
            {{i18n "admin.wizard.review.reject_modal.send_email"}}
          </label>
        </div>
      </:body>

      <:footer>
        <DButton
          @icon="xmark"
          @action={{this.perform}}
          @label="admin.wizard.review.reject_modal.confirm"
          class="btn-danger"
        />
        <DButton @action={{@closeModal}} @label="cancel" class="cancel" />
      </:footer>
    </DModal>
  </template>
}
