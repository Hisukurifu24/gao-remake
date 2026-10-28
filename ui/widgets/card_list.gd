class_name CardList
extends VBoxContainer
## A column of cards -- save slots, the ways to play -- with one cursor over it.
##
## The card the cursor is on is lit -- an orange line round a warm fill -- the rest
## are the plain inset; both have the same margins, so nothing moves a pixel as the
## cursor does. The cards themselves are whatever [PanelContainer]s the screen
## builds: this only owns which one is lit, and the mouse, which drives the same
## cursor as the keys -- hovering a card selects it, clicking chooses it.

signal chosen(index: int)
signal moved(index: int)

const LIT := &"CardLit"
const UNLIT := &"InsetPanel"

var index := 0
var _cards: Array[PanelContainer] = []


func _init() -> void:
	add_theme_constant_override(&"separation", 6)


## Replaces the cards. [param keep_cursor] leaves the cursor where it was.
func set_cards(cards: Array[PanelContainer], keep_cursor := false) -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards = cards
	for i in cards.size():
		var card := cards[i]
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_entered.connect(_moved_to.bind(i))
		card.gui_input.connect(_on_card_input.bind(i))
		add_child(card)
	index = clampi(index if keep_cursor else 0, 0, maxi(0, cards.size() - 1))
	_paint()


func card_count() -> int:
	return _cards.size()


func card(at: int) -> PanelContainer:
	return _cards[at] if at >= 0 and at < _cards.size() else null


## The cursor moved by the player, which is heard; [method select] is the page
## putting it somewhere, which isn't.
func move(by: int) -> void:
	_moved_to(index + by)


func _moved_to(at: int) -> void:
	var was := index
	select(at)
	if index != was:
		Audio.play(&"move")


func select(at: int) -> void:
	if _cards.is_empty():
		return
	at = clampi(at, 0, _cards.size() - 1)
	if at == index:
		return
	index = at
	_paint()
	moved.emit(index)


func choose() -> void:
	if index >= 0 and index < _cards.size():
		Audio.play(&"accept")
		chosen.emit(index)


func _paint() -> void:
	for i in _cards.size():
		var variation := LIT if i == index else UNLIT
		if _cards[i].theme_type_variation != variation:
			_cards[i].theme_type_variation = variation


func _on_card_input(event: InputEvent, at: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	match click.button_index:
		MOUSE_BUTTON_LEFT:
			select(at)
			choose()
		MOUSE_BUTTON_WHEEL_UP:
			move(-1)
		MOUSE_BUTTON_WHEEL_DOWN:
			move(1)
