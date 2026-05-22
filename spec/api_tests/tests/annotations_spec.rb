require_relative '../loader'

describe 'annotations' do
  it 'tests custom annotation' do
    expect(GenericApi.render.anon_test[:data]).to eq(12345)
  end
end