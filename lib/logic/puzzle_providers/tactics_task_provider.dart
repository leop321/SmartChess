import '../../model/tactics_task.dart';

abstract class TacticsTaskProvider {
  Future<TacticsTask> fetchNextTask();
  Future<TacticsTask> fetchTaskById(String id);
}
