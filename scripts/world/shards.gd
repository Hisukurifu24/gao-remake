class_name Shards
## A sprite breaking into shards of light, as SAO draws a death: the avatar
## logged out ([code]ui/signal_lost.gd[/code]), the last boss after his last words
## ([FoeFigure]). View only; the shards free themselves.

## SAO's blue-white.
const COLOURS: Array[Color] = [UiPalette.GLASS_SELECTED, UiPalette.MAP_EDGE, UiPalette.FIELD]


## [param sprite] gone, and [param count] shards flying out of where it was, on
## [param parent], for [param time] seconds. Global RNG: behaviour, not generation.
static func burst(sprite: Sprite2D, parent: Node2D, count: int, time: float) -> void:
	sprite.self_modulate.a = 0.0
	var box := sprite.get_rect()
	# A bigger body throws bigger shards, further.
	var reach := maxf(1.0, box.size.y / 16.0)
	for i in count:
		var shard := Polygon2D.new()
		var size := randf_range(1.0, 2.5) * sqrt(reach)
		shard.polygon = PackedVector2Array([
			Vector2(0, -size), Vector2(size * 0.9, size * 0.6), Vector2(-size * 0.9, size * 0.6)])
		shard.color = COLOURS[randi() % COLOURS.size()]
		shard.z_index = 20
		var from := Vector2(randf_range(box.position.x, box.end.x), randf_range(box.position.y, box.end.y))
		shard.position = parent.to_local(sprite.to_global(from))
		shard.rotation = randf() * TAU
		parent.add_child(shard)
		var away := (from - box.get_center()).normalized()
		if away.is_zero_approx():
			away = Vector2.UP
		var fly := shard.create_tween().set_parallel()
		fly.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fly.tween_property(shard, "position", shard.position
				+ away * randf_range(10.0, 28.0) * reach + Vector2(0, -randf_range(4.0, 18.0) * reach), time)
		fly.tween_property(shard, "rotation", shard.rotation + randf_range(-6.0, 6.0), time)
		fly.tween_property(shard, "modulate:a", 0.0, time * 0.6).set_delay(time * 0.4)
		fly.chain().tween_callback(shard.queue_free)
