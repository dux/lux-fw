# http://sequel.jeremyevans.net/rdoc/classes/Sequel/Inflections.html

String.inflections do |inflect|
  inflect.plural   'bonus', 'bonuses'
  inflect.plural   'clothing', 'clothes'
  inflect.plural   'people', 'people'
  inflect.singular /news$/, 'news'
end
