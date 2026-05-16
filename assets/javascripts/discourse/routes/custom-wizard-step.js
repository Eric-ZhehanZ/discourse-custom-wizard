import { action } from "@ember/object";
import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { scrollTop } from "discourse/lib/scroll-top";
import I18n from "I18n";
import { getCachedWizard } from "../models/custom-wizard";

export default Route.extend({
  router: service(),

  beforeModel() {
    const wizard = getCachedWizard();
    this.set("wizard", wizard);

    if (!wizard || !wizard.permitted) {
      this.router.replaceWith("customWizard");
      return;
    }

    // An "approved" wizard whose submission was marked submitted_at is
    // technically `completed`, but the user just clicked
    // "Update my information again" — bouncing them back to the
    // status page would look like a stray refresh. Allow the form to
    // render whenever the wizard is in a review state, regardless of
    // the completion marker.
    const inReview = wizard.review_state && wizard.review_state !== "none";
    if (wizard.completed && !inReview) {
      this.router.replaceWith("customWizard");
    }
  },

  model(params) {
    const wizard = this.wizard;

    if (wizard && wizard.steps) {
      const step = wizard.steps.findBy("id", params.step_id);
      return step ? step : wizard.steps[0];
    } else {
      return wizard;
    }
  },

  afterModel(model) {
    if (model.completed) {
      return this.router.transitionTo("wizard.index");
    }
    return model.set("wizardId", this.wizard.id);
  },

  setupController(controller, model) {
    let props = {
      step: model,
      wizard: this.wizard,
    };

    if (!model.permitted) {
      props["stepMessage"] = {
        state: "not-permitted",
        text: model.permitted_message || I18n.t("wizard.step_not_permitted"),
      };
      if (model.index > 0) {
        props["showReset"] = true;
      }
    }

    controller.setProperties(props);
  },

  @action
  didTransition() {
    scrollTop();
    return true;
  },
});
