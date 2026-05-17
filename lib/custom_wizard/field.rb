# frozen_string_literal: true

class CustomWizard::Field
  include ActiveModel::SerializerSupport

  attr_reader :raw,
              :id,
              :type,
              :required,
              :value,
              :description,
              :image,
              :image_upload_id,
              :validations,
              :min_length,
              :max_length,
              :char_counter,
              :file_types,
              :max_upload_size_kb,
              :max_image_dimension,
              :compress_images,
              :convert_heic,
              :format,
              :limit,
              :property,
              :content,
              :tag_groups,
              :category,
              :can_create_tag,
              :preview_template,
              :placeholder,
              :regex,
              :regex_message,
              :min,
              :max,
              :step_size

  attr_accessor :index, :step

  REQUIRES_USER = %w[upload]

  def initialize(attrs)
    @raw = attrs || {}
    @id = attrs[:id]
    @index = attrs[:index]
    @type = attrs[:type]
    @required = !!attrs[:required]
    @value = attrs[:value] || default_value
    @description = attrs[:description]
    @image = attrs[:image]
    @validations = attrs[:validations]
    @min_length = attrs[:min_length]
    @max_length = attrs[:max_length]
    @char_counter = attrs[:char_counter]
    @file_types = attrs[:file_types]
    @max_upload_size_kb = attrs[:max_upload_size_kb]
    @max_image_dimension = attrs[:max_image_dimension]
    @compress_images = attrs[:compress_images]
    @convert_heic = attrs[:convert_heic]
    @format = attrs[:format]
    @limit = attrs[:limit]
    @property = attrs[:property]
    @content = attrs[:content]
    @tag_groups = attrs[:tag_groups]
    @category = attrs[:category]
    @can_create_tag = attrs[:can_create_tag]
    @preview_template = attrs[:preview_template]
    @placeholder = attrs[:placeholder]
    @regex = attrs[:regex]
    @regex_message = attrs[:regex_message]
    @min = attrs[:min]
    @max = attrs[:max]
    # `step` shadows the wizard's Step accessor; expose it as
    # `step_size` to the rest of the plugin.
    @step_size = attrs[:step]
  end

  def label
    @label ||= PrettyText.cook(@raw[:label])
  end

  def default_value
    false if @type == "checkbox"
  end

  def self.types
    @types ||= {
      text: {
        min_length: nil,
        max_length: nil,
        prefill: nil,
        char_counter: nil,
        validations: nil,
        placeholder: nil,
        regex: nil,
        regex_message: nil,
      },
      textarea: {
        min_length: nil,
        max_length: nil,
        prefill: nil,
        char_counter: nil,
        placeholder: nil,
        regex: nil,
        regex_message: nil,
      },
      composer: {
        min_length: nil,
        max_length: nil,
        char_counter: nil,
        placeholder: nil,
      },
      text_only: {
      },
      composer_preview: {
        preview_template: nil,
      },
      date: {
        format: "YYYY-MM-DD",
        prefill: nil,
      },
      time: {
        format: "HH:mm",
        prefill: nil,
      },
      date_time: {
        format: "",
        prefill: nil,
      },
      number: {
        prefill: nil,
        placeholder: nil,
        min: nil,
        max: nil,
        min_length: nil,
        max_length: nil,
        step: nil,
      },
      checkbox: {
        prefill: nil,
      },
      url: {
        min_length: nil,
        prefill: nil,
        placeholder: nil,
        regex: nil,
        regex_message: nil,
      },
      upload: {
        file_types: ".jpg,.jpeg,.png",
        max_upload_size_kb: nil,
        max_image_dimension: nil,
        compress_images: nil,
        convert_heic: nil,
      },
      dropdown: {
        prefill: nil,
        content: nil,
        content_source: nil,
        content_text: nil,
        content_url: nil,
        content_separator: nil,
      },
      tag: {
        limit: nil,
        prefill: nil,
        content: nil,
        content_source: nil,
        content_text: nil,
        content_url: nil,
        content_separator: nil,
        tag_groups: nil,
        can_create_tag: false,
      },
      category: {
        limit: 1,
        property: "id",
        prefill: nil,
        content: nil,
        content_source: nil,
        content_text: nil,
        content_url: nil,
        content_separator: nil,
      },
      topic: {
        limit: 1,
        prefill: nil,
        content: nil,
        content_source: nil,
        content_text: nil,
        content_url: nil,
        content_separator: nil,
        category: nil,
      },
      group: {
        prefill: nil,
        content: nil,
        content_source: nil,
        content_text: nil,
        content_url: nil,
        content_separator: nil,
      },
      user_selector: {
      },
    }
  end

  def self.require_assets
    Rails.logger.warn(
      "Custom Wizard field regisration no longer requires asset registration. Support will be removed in v2.1.0.",
    )

    @require_assets ||= {}
  end

  def self.register(type, plugin = nil, opts = {}, legacy_opts = {})
    if opts.is_a?(Array)
      Rails.logger.warn(
        "Custom Wizard field regisration no longer requires asset registration. Support will be removed in v2.1.0.",
      )

      require_assets[plugin] = opts
      opts = legacy_opts
    end

    if type
      types[type.to_sym] ||= {}
      types[type.to_sym] = opts[:type_opts] if opts[:type_opts].present?
    end
  end
end
