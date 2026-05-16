import { registerReviewableActionModal } from "discourse/components/reviewable/item";
import WizardRejectReasonModal from "../components/modal/wizard-reject-reason";

// Open our purpose-built reject-with-reason modal when a moderator
// clicks Reject on a wizard submission. The reason flows through the
// perform endpoint's `reject_reason` arg (set on the reviewable by the
// modal) into the denial system message.
export default {
  name: "wizard-reviewable-reject-modal",
  initialize() {
    registerReviewableActionModal(
      "reject_wizard_submission",
      WizardRejectReasonModal
    );
  },
};
