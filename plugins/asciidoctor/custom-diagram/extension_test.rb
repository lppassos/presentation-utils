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

def radial_team_diagram
  PresentationUtils::CustomDiagram::RadialTeamDiagram.new
end

class TestCustomDiagramParser < Minitest::Test
  def test_ignores_empty_lines_and_detects_type
    data = custom_diagram_parser.parse(["  \n", ' radial-team ', ' Alice, Architect '])

    assert_equal 'radial-team', data['type']
    assert_equal 'Team', data['title']
    assert_equal [{ 'name' => 'Alice', 'role' => 'Architect' }], data['members']
  end

  def test_reads_radial_team_title_from_first_line
    data = custom_diagram_parser.parse("radial-team\ntitle Platform Team\nAlice, Architect")

    assert_equal 'Platform Team', data['title']
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

  def test_renderer_uses_document_attribute_setting
    renderer = radial_team_diagram
    document = FakeCustomDiagramDocument.new('custom-diagram-center-fill' => '#112233')
    data = { 'type' => 'radial-team', 'title' => 'Team', 'members' => [{ 'name' => 'Alice', 'role' => 'Architect' }] }

    svg = renderer.render(document, data)

    assert_includes svg, 'fill="#112233"'
  end

  def test_render_radial_team_svg_contains_expected_content
    renderer = radial_team_diagram
    document = FakeCustomDiagramDocument.new(
      'base-font-family' => 'Test Sans',
      'custom-diagram-radial-member-fill' => '#111111',
      'custom-diagram-radial-member-stroke' => '#222222',
      'custom-diagram-radial-member-text-color' => '#444444',
      'custom-diagram-radial-member-role-color' => '#555555',
      'custom-diagram-radial-connector-color' => '#333333'
    )
    data = {
      'type' => 'radial-team',
      'title' => 'Platform Team',
      'members' => [
        { 'name' => 'Alice & Bob', 'role' => 'Architecture' },
        { 'name' => 'Carol', 'role' => 'Delivery' }
      ]
    }

    svg = renderer.render(document, data)

    assert_includes svg, '<svg'
    assert_includes svg, 'Platform Team'
    assert_includes svg, 'Alice &amp; Bob'
    assert_includes svg, 'Architecture'
    assert_includes svg, 'stroke="#333333"'
    assert_includes svg, 'stroke="#222222"'
    assert_includes svg, 'fill="#111111"'
    assert_includes svg, 'fill="#444444">Alice &amp; Bob<'
    assert_includes svg, 'fill="#555555">Architecture<'
  end

  def test_render_unknown_svg_escapes_type
    converter = custom_diagram_converter
    svg = converter.render_svg(FakeCustomDiagramDocument.new, { 'type' => '<bad>' })

    assert_includes svg, '&lt;bad&gt;'
  end

  def test_radial_team_layout_uses_top_and_bottom_rows_with_centered_connector_span
    renderer = radial_team_diagram
    layout = renderer.send(:layout, [
                             { 'name' => 'A', 'role' => 'R' },
                             { 'name' => 'B', 'role' => 'R' },
                             { 'name' => 'C', 'role' => 'R' },
                             { 'name' => 'D', 'role' => 'R' }
                           ], {})

    top_row = layout[:members].select { |member| member[:y] < layout[:center_y] }
    bottom_row = layout[:members].select { |member| member[:y] > layout[:center_y] }

    assert_equal 2, top_row.length
    assert_equal 2, bottom_row.length
    assert_equal [top_row[0][:y] + layout[:member_height] + 5, layout[:center_y] - 5, layout[:center_x] + 115],
                 [top_row[0][:connector_start_y], top_row[0][:connector_end_y], top_row[0][:connector_end_x]]
    assert_equal [top_row[1][:y] + layout[:member_height] + 5, layout[:center_y] - 5, layout[:center_x] + 145],
                 [top_row[1][:connector_start_y], top_row[1][:connector_end_y], top_row[1][:connector_end_x]]
    assert_equal [bottom_row[0][:y] - 5, layout[:center_y] + layout[:center_height] + 5, layout[:center_x] + 115],
                 [bottom_row[0][:connector_start_y], bottom_row[0][:connector_end_y], bottom_row[0][:connector_end_x]]
    assert_equal [bottom_row[1][:y] - 5, layout[:center_y] + layout[:center_height] + 5, layout[:center_x] + 145],
                 [bottom_row[1][:connector_start_y], bottom_row[1][:connector_end_y], bottom_row[1][:connector_end_x]]
  end

  def test_radial_team_connector_path_elbows_when_x_differs
    renderer = radial_team_diagram

    elbow = renderer.send(:connector_geometry, 10, 20, 50, 100)
    straight = renderer.send(:connector_geometry, 10, 20, 10, 100)

    assert_equal 25, elbow[:start_circle_y]
    assert_equal 95, elbow[:end_circle_y]
    assert_equal 'M 10 25 L 10.0 52.0 Q 10 60 18.0 60.0 L 42.0 60.0 Q 50 60 50.0 68.0 L 50 95', elbow[:path]
    assert_equal 25, straight[:start_circle_y]
    assert_equal 95, straight[:end_circle_y]
    assert_equal 'M 10 25 L 10 95', straight[:path]
  end
end
