# frozen_string_literal: true

describe CustomWizard::Field do
  let(:field_hash) { get_wizard_fixture("field/field") }

  before do
    CustomWizard::Field.register(
      "location",
      "discourse-locations",
      %w[components helpers lib stylesheets templates],
      type_opts: {
        prefill: {
          coordinates: [35.3082, 149.1244],
        },
      },
    )
  end

  it "initialize custom field attributes" do
    field = CustomWizard::Field.new(field_hash)
    expect(field.id).to eq("field_id")
    expect(field.index).to eq(0)
    expect(field.label).to eq("<p>Field Label</p>")
    expect(field.image).to eq("field_image_url.png")
    expect(field.description).to eq("Field description")
    expect(field.required).to eq(true)
    expect(field.type).to eq("field_type")
    expect(field.content).to eq([])
  end

  it "registers custom field types" do
    expect(CustomWizard::Field.types[:location].present?).to eq(true)
  end

  it "allows custom field types to set default attributes" do
    expect(CustomWizard::Field.types[:location][:prefill]).to eq(
      { coordinates: [35.3082, 149.1244] },
    )
  end

  it "registers custom field assets" do
    expect(CustomWizard::Field.require_assets["discourse-locations"]).to eq(
      %w[components helpers lib stylesheets templates],
    )
  end

  describe "upload field options" do
    it "exposes the new per-field size and transform options" do
      field =
        CustomWizard::Field.new(
          id: "upload_field",
          type: "upload",
          max_upload_size_kb: 2048,
          max_image_dimension: 1600,
          compress_images: true,
          convert_heic: true,
        )

      expect(field.max_upload_size_kb).to eq(2048)
      expect(field.max_image_dimension).to eq(1600)
      expect(field.compress_images).to eq(true)
      expect(field.convert_heic).to eq(true)
    end

    it "registers default upload type attributes" do
      upload_defaults = CustomWizard::Field.types[:upload]
      expect(upload_defaults).to include(
        :file_types,
        :max_upload_size_kb,
        :max_image_dimension,
        :compress_images,
        :convert_heic,
      )
    end
  end
end
