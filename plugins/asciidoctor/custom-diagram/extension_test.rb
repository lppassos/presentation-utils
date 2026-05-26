require 'minitest/autorun'
require 'tmpdir'

require_relative 'extension'

class FakeCustomDiagramDocument
  def initialize(attrs = {})
    @attrs = attrs
  end

  def attr(name, default = nil)
    @attrs.fetch(name.to_s, default)
  end
end

def custom_diagram_parser
  PresentationUtils::CustomDiagram::Parser.new
end

def custom_diagram_converter
  PresentationUtils::CustomDiagram::CustomDiagramBlockConverter.allocate
end

class TestCustomDiagramParser < Minitest::Test
  def test_ignores_empty_lines_and_detects_type
    data = custom_diagram_parser.parse(["  \n", ' radial-team ', ' Alice, Architect '])

    assert_equal 'radial-team', data['type']
    assert_equal [{ 'name' => 'Alice', 'role' => 'Architect' }], data['members']
  end

  def test_parses_role_with_additional_commas
    data = custom_diagram_parser.parse("radial-team\nAlice, Architect, Platform")

    assert_equal 'Alice', data['members'][0]['name']
    assert_equal 'Architect, Platform', data['members'][0]['role']
  end

  def test_skips_invalid_member_lines
    data = custom_diagram_parser.parse("radial-team\nAlice\n, Missing name\nBob, Delivery")

    assert_equal [{ 'name' => 'Bob', 'role' => 'Delivery' }], data['members']
  end
end

class TestCustomDiagramConverter < Minitest::Test
  def test_normalize_target_forces_svg_extension
    converter = custom_diagram_converter

    assert_equal 'team.svg', converter.normalize_target('team.png')
    assert_equal 'team.svg', converter.normalize_target('team')
  end

  def test_resolve_output_path_uses_imagesoutdir
    Dir.mktmpdir do |dir|
      converter = custom_diagram_converter
      document = FakeCustomDiagramDocument.new('docdir' => dir, 'imagesoutdir' => '.imggen')

      assert_equal File.join(dir, '.imggen', 'team.svg'), converter.resolve_output_path(document, 'team.svg')
    end
  end

  def test_document_attribute_overrides_theme_setting
    converter = custom_diagram_converter
    document = FakeCustomDiagramDocument.new('custom-diagram-center-fill' => '#112233')

    assert_equal '#112233',
                 converter.get_setting(document, 'custom-diagram-center-fill', :custom_diagram_center_fill, '#ffffff')
  end

  def test_render_radial_team_svg_contains_expected_content
    converter = custom_diagram_converter
    document = FakeCustomDiagramDocument.new(
      'base-font-family' => 'Test Sans',
      'custom-diagram-member-palette' => '#111111,#222222',
      'custom-diagram-connector-color' => '#333333'
    )
    data = {
      'type' => 'radial-team',
      'members' => [
        { 'name' => 'Alice & Bob', 'role' => 'Architecture' },
        { 'name' => 'Carol', 'role' => 'Delivery' }
      ]
    }

    svg = converter.render_svg(document, data)

    assert_includes svg, '<svg'
    assert_includes svg, 'Alice &amp; Bob'
    assert_includes svg, 'Architecture'
    assert_includes svg, 'stroke="#333333"'
    assert_includes svg, 'fill="#111111"'
    assert_includes svg, 'fill="#222222"'
  end

  def test_render_unknown_svg_escapes_type
    converter = custom_diagram_converter
    svg = converter.render_svg(FakeCustomDiagramDocument.new, { 'type' => '<bad>' })

    assert_includes svg, '&lt;bad&gt;'
  end
end
