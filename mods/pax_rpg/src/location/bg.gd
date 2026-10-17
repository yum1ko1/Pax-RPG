extends RefCounted
## Посчитать в потоке и дождаться, не замораживая кадр: var r = await Bg.run(func() -> Variant: return heavy()).
## Свой опрос задачи каждым кадром (WorkerThreadPool), как Jobs.await_work игры. Pax.jobs.background не годится:
## его результаты раздаёт Jobs.poll(), а его в игре никто не зовёт — done не приходил, загрузка висела.
## Задача — чистая функция: без узлов, мода и общих словарей. Ошибка в задаче — вернётся null.

## Потоки мода пока выключены: с обновления игры 0.31.4 она падает, пока задача мода считается в потоке
## (след: «landscape: compute [поток]» — и тишина). Без потока — считаем в кадре (короткая заминка).
const THREADS := false


static func run(work: Callable) -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if not THREADS:
		await tree.process_frame
		return work.call()
	var box: Array = []
	var task := WorkerThreadPool.add_task(func() -> void: box.append(work.call()), false, "pax_rpg")
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return box[0] if not box.is_empty() else null
