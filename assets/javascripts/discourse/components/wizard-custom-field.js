import Component from "@ember/component";
import { computed } from "@ember/object";
import { equal, or } from "@ember/object/computed";
import I18n from "I18n";
import { default as discourseComputed } from "discourse-common/utils/decorators";
import { selectKitContent } from "../lib/wizard";
import wizardSchema from "../lib/wizard-schema";
import UndoChanges from "../mixins/undo-changes";

const CONTENT_SOURCE_TYPES = ["mapper", "text", "remote"];

export default Component.extend(UndoChanges, {
  componentType: "field",
  classNameBindings: [":wizard-custom-field", "visible"],
  visible: computed("currentFieldId", function () {
    return this.field.id === this.currentFieldId;
  }),
  isDropdown: equal("field.type", "dropdown"),
  isUpload: equal("field.type", "upload"),
  isCategory: equal("field.type", "category"),
  isTopic: equal("field.type", "topic"),
  isGroup: equal("field.type", "group"),
  isTag: equal("field.type", "tag"),
  isText: equal("field.type", "text"),
  isTextarea: equal("field.type", "textarea"),
  isUrl: equal("field.type", "url"),
  isComposer: equal("field.type", "composer"),
  isNumber: equal("field.type", "number"),
  isCheckbox: equal("field.type", "checkbox"),
  isDate: equal("field.type", "date"),
  isTime: equal("field.type", "time"),
  isFullDateTime: equal("field.type", "date_time"),
  isRegexable: or("isText", "isTextarea", "isUrl"),
  hasPlaceholder: or("isText", "isTextarea", "isComposer", "isUrl", "isNumber"),
  showPrefill: or(
    "isText",
    "isTextarea",
    "isCategory",
    "isTag",
    "isGroup",
    "isDropdown",
    "isTopic",
    "isUrl",
    "isNumber",
    "isCheckbox",
    "isDate",
    "isTime",
    "isFullDateTime"
  ),
  showContent: or("isCategory", "isTag", "isGroup", "isDropdown", "isTopic"),
  contentSourceIsMapper: computed("field.content_source", function () {
    const v = this.field.content_source;
    return !v || v === "mapper";
  }),
  contentSourceIsText: equal("field.content_source", "text"),
  contentSourceIsRemote: equal("field.content_source", "remote"),
  contentSourceIsBulk: or("contentSourceIsText", "contentSourceIsRemote"),
  contentSourceTypes: computed(function () {
    return CONTENT_SOURCE_TYPES.map((id) => ({
      id,
      name: I18n.t(`admin.wizard.field.content_source_types.${id}`),
    }));
  }),
  showLimit: or("isCategory", "isTag", "isTopic"),
  isTextType: or("isText", "isTextarea", "isComposer"),
  isComposerPreview: equal("field.type", "composer_preview"),
  categoryPropertyTypes: selectKitContent(["id", "slug"]),
  messageUrl:
    "https://pavilion.tech/products/discourse-custom-wizard-plugin/documentation/field-settings",

  @discourseComputed("field.type")
  validations(type) {
    const applicableToField = [];

    for (let validation in wizardSchema.field.validations) {
      if (wizardSchema.field.validations[validation]["types"].includes(type)) {
        applicableToField.push(validation);
      }
    }

    return applicableToField;
  },

  @discourseComputed("field.type")
  isDateTime(type) {
    return ["date_time", "date", "time"].indexOf(type) > -1;
  },

  @discourseComputed("field.type")
  messageKey(type) {
    let key = "type";
    if (type) {
      key = "edit";
    }
    return key;
  },

  setupTypeOutput(fieldType, options) {
    const selectionType = {
      category: "category",
      tag: "tag",
      group: "group",
    }[fieldType];

    if (selectionType) {
      options[`${selectionType}Selection`] = "output";
      options.outputDefaultSelection = selectionType;
    }

    return options;
  },

  @discourseComputed("field.type")
  contentOptions(fieldType) {
    let options = {
      wizardFieldSelection: true,
      textSelection: "key,value",
      userFieldSelection: "key,value",
      context: "field",
    };

    options = this.setupTypeOutput(fieldType, options);

    if (this.isDropdown) {
      options.wizardFieldSelection = "key,value";
      options.userFieldOptionsSelection = "output";
      options.textSelection = "key,value";
      options.inputTypes = "association,conditional,assignment";
      options.pairConnector = "association";
      options.keyPlaceholder = "admin.wizard.key";
      options.valuePlaceholder = "admin.wizard.value";
    }

    return options;
  },

  @discourseComputed("field.type")
  prefillOptions(fieldType) {
    let options = {
      wizardFieldSelection: true,
      textSelection: true,
      // Enable userField for every selector slot (incl. the assignment
      // output), so prefill can grab the current user's name /
      // username / email / bio / custom user fields — same as
      // conditions already do. The previous "key,value" restricted
      // it to pair positions which never appear in a prefill input.
      userFieldSelection: true,
      userFieldOptionsSelection: true,
      customFieldSelection: true,
      context: "field",
    };

    return this.setupTypeOutput(fieldType, options);
  },

  @discourseComputed("step.index")
  fieldConditionOptions(stepIndex) {
    const options = {
      inputTypes: "validation",
      context: "field",
      textSelection: "value",
      userFieldSelection: true,
      groupSelection: true,
    };

    if (stepIndex > 0) {
      options.wizardFieldSelection = true;
      options.wizardActionSelection = true;
    }

    return options;
  },

  @discourseComputed("step.index")
  fieldIndexOptions(stepIndex) {
    const options = {
      context: "field",
      userFieldSelection: true,
      groupSelection: true,
    };

    if (stepIndex > 0) {
      options.wizardFieldSelection = true;
      options.wizardActionSelection = true;
    }

    return options;
  },

  actions: {
    imageUploadDone(upload) {
      this.setProperties({
        "field.image": upload.url,
        "field.image_upload_id": upload.id,
      });
    },

    imageUploadDeleted() {
      this.setProperties({
        "field.image": null,
        "field.image_upload_id": null,
      });
    },

    changeCategory(category) {
      this.set("field.category", category?.id);
    },

    contentSourceChanged(value) {
      this.set("field.content_source", value);
    },
  },
});
