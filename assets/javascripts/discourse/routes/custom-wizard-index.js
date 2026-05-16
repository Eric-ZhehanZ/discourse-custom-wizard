import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { getCachedWizard } from "../models/custom-wizard";

export default Route.extend({
  router: service(),

  beforeModel() {
    const wizard = getCachedWizard();
    if (!wizard) return;

    // Any user with a review state (approved / pending / denied) lands
    // on the status page instead of the form. They can opt into the
    // form from the status page's secondary link.
    if (wizard.review_state && wizard.review_state !== "none") return;

    if (wizard.permitted && !wizard.completed && wizard.start) {
      this.router.replaceWith("customWizardStep", wizard.start);
    }
  },

  model() {
    return getCachedWizard();
  },

  setupController(controller, model) {
    if (model && model.id) {
      const completed = model.get("completed");
      const permitted = model.get("permitted");
      const wizardId = model.get("id");
      const user = model.get("user");
      const name = model.get("name");
      const requiresLogin = !user && !permitted;
      const notPermitted = !permitted;
      const reviewState = model.get("review_state") || "none";
      const previouslyApproved = !!model.get("previously_approved");

      const props = {
        wizardModel: model,
        requiresLogin,
        user,
        name,
        completed,
        notPermitted,
        wizardId,
        reviewState,
        previouslyApproved,
      };
      controller.setProperties(props);
    } else {
      controller.set("noWizard", true);
    }
  },
});
