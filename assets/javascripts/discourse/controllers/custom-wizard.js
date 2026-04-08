import Controller from "@ember/controller";
import { service } from "@ember/service";

export default Controller.extend({
  wizardState: service(),
  queryParams: ["reset"],
});
