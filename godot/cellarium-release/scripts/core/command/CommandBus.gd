extends Node
## 唯一写入口。UI / Agent / 回放共用同一命令对象；enqueue() 只入队，
## 真实写入在下一 tick 由 execute_tick_commands() 完成。
## DIVIDE 与 REPRODUCE 使用不同 type，由命令执行器分别处理。

signal command_executed(command: Dictionary, tick_index: int)

var _pending: Array[Dictionary] = []

func enqueue(command: Dictionary) -> void:
	if command.is_empty():
		return
	_pending.append(command.duplicate(true))

func pending_count() -> int:
	return _pending.size()

func execute_tick_commands(tick_index: int) -> int:
	var batch: Array[Dictionary] = _pending
	_pending = []
	for cmd in batch:
		var typed_cmd: Dictionary = cmd
		command_executed.emit(typed_cmd, tick_index)
	return batch.size()
