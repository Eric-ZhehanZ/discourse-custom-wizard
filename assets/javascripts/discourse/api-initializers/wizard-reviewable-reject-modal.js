import RejectReasonReviewableModal from "discourse/components/modal/reject-reason-reviewable";
import { registerReviewableActionModal } from "discourse/components/reviewable/item";

// Open the standard "reject with reason" modal when a moderator clicks
// Reject on a wizard submission, so they can attach a free-form reason
// (and decide whether to email the user). The reason is forwarded via
// the perform endpoint's `reject_reason` arg, which
// ReviewableCustomWizardSubmission#perform_reject_wizard_submission
// already passes into the system message template.
export default {
  name: "wizard-reviewable-reject-modal",
  initialize() {
    registerReviewableActionModal(
      "reject_wizard_submission",
      RejectReasonReviewableModal
    );
  },
};
