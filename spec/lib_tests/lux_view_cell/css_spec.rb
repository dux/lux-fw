require 'spec_helper'

class FooCell < Lux::ViewCell
  css %[
    .foo1 {
      .bar {
        font-weight: bold;
      }
    }
  ]

  css %[
    .bold { font-weight: bold; }
  ]
end

class BarCell < Lux::ViewCell
  css %[
    .baz1 {
      .baz2 {
        font-weight: bold;
      }
    }
  ]
end

describe 'Lux::ViewCell css' do
  it 'compiles' do
    css = Lux::ViewCell.css
    # DATA[:css] is shared across all cells; assert per-cell contributions are present.
    expect(css).to include('.foo1 .bar')
    expect(css).to include('.bold')
    expect(css).to include('.baz1 .baz2')
  end
end
