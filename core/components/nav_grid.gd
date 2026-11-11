class_name NavGrid
extends Node3D
## Mapa del campo de batalla en celdas libres u ocupadas, para que los tanques de la máquina
## calculen rutas que rodean edificios, setos, colinas y recintos cerrados (AStarGrid2D).
## Se rellena preguntando a la física qué hay en cada celda y se repasa sin parar, unas pocas
## filas por fotograma, así que lo que se destruye deja de estorbar al cabo de unos segundos.
## Los tanques no cuentan como obstáculo aquí: de esquivarlos se ocupa AIBrain.

const HALF: float = 200.0
const CELL: float = 4.0
const SIZE: int = 100
## Holgura alrededor de cada celda: un obstáculo a menos de esta distancia la da por ocupada.
const MARGIN: float = 1.8
const WORLD_MASK: int = 1

## Ya se ha recorrido el mapa entero al menos una vez.
var ready_once: bool = false

var _astar := AStarGrid2D.new()
var _shape := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _row: int = 0
var _tick: int = 0


## El mapa de un escenario (lo crea la primera vez que se pide).
static func of(world: Node) -> NavGrid:
	var grid: NavGrid = world.get_node_or_null("NavGrid") as NavGrid
	if grid == null:
		grid = NavGrid.new()
		grid.name = "NavGrid"
		world.add_child(grid)
	return grid


func _init() -> void:
	_astar.region = Rect2i(0, 0, SIZE, SIZE)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	_shape.size = Vector3(CELL + MARGIN * 2.0, 1.2, CELL + MARGIN * 2.0)
	_query.shape = _shape
	_query.collision_mask = WORLD_MASK


func _physics_process(_delta: float) -> void:
	# Primera pasada rápida (medio segundo); después, una fila cada dos fotogramas.
	var rows: int = 4
	if ready_once:
		_tick += 1
		rows = 1 if _tick % 2 == 0 else 0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for i in rows:
		_scan_row(space, _row)
		_row += 1
		if _row >= SIZE:
			_row = 0
			ready_once = true


func _scan_row(space: PhysicsDirectSpaceState3D, row: int) -> void:
	for column in SIZE:
		# La caja va de 0,4 a 1,6 m de altura: no toca el suelo y sí todo lo que frena a un tanque.
		_query.transform = Transform3D(Basis(), cell_center(Vector2i(column, row)) + Vector3.UP)
		var solid: bool = false
		for hit in space.intersect_shape(_query, 6):
			var collider: Object = hit["collider"]
			if collider is Destructible and (collider as Destructible).crushable:
				continue
			solid = true
			break
		_astar.set_point_solid(Vector2i(column, row), solid)


func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(clampi(floori((point.x + HALF) / CELL), 0, SIZE - 1), clampi(floori((point.z + HALF) / CELL), 0, SIZE - 1))


func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(-HALF + (cell.x + 0.5) * CELL, 0.0, -HALF + (cell.y + 0.5) * CELL)


## Ruta de `from` a `to` como puntos del mundo; el último es el propio destino. Vacía si no
## hay paso. Si un extremo cae en una celda ocupada se usa la celda libre más cercana.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array()
	var start: Vector2i = nearest_free(cell_of(from))
	var goal: Vector2i = nearest_free(cell_of(to))
	if start.x < 0 or goal.x < 0:
		return path
	for cell: Vector2i in _astar.get_id_path(start, goal):
		path.append(cell_center(cell))
	if not path.is_empty():
		path.append(Vector3(to.x, 0.0, to.z))
	return path


func nearest_free(cell: Vector2i) -> Vector2i:
	if not _astar.is_point_solid(cell):
		return cell
	var best := Vector2i(-1, -1)
	var best_distance: int = 999999
	for radius in range(1, 7):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var other := cell + Vector2i(dx, dy)
				if other.x < 0 or other.y < 0 or other.x >= SIZE or other.y >= SIZE or _astar.is_point_solid(other):
					continue
				var distance: int = dx * dx + dy * dy
				if distance < best_distance:
					best_distance = distance
					best = other
		if best.x >= 0:
			return best
	return best
