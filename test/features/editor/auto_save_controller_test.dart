import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:quki_notes/features/editor/auto_save_controller.dart';

const _debounce = Duration(milliseconds: 20);
const _periodic = Duration(milliseconds: 100);
const _debounceWait = Duration(milliseconds: 60);
const _periodicWait = Duration(milliseconds: 250);

/// A simple in-memory store that mimics what the real onSave callback does.
class _FakeStore {
  String? id;
  String body = '';
  int callCount = 0;
  bool shouldThrow = false;

  Future<String> onSave(String? currentId, String newBody) async {
    callCount++;
    if (shouldThrow) throw Exception('write failed');
    body = newBody;
    if (currentId != null) {
      id = currentId;
      return currentId;
    }
    id ??= 'new-id-$callCount';
    return id!;
  }
}

void main() {
  late _FakeStore store;
  late AutoSaveController controller;
  var body = '';

  AutoSaveController makeController({String? initialId}) {
    store = _FakeStore()..id = initialId;
    controller = AutoSaveController(
      onSave: store.onSave,
      getBody: () => body,
      initialId: initialId,
      debounceDelay: _debounce,
      periodicInterval: _periodic,
    );
    return controller;
  }

  setUp(() {
    body = '';
  });

  tearDown(() {
    controller.dispose();
  });

  group('AutoSaveController.save', () {
    test('does nothing when body is empty', () async {
      makeController();
      controller.start();
      await controller.save();
      expect(store.callCount, 0);
    });

    test('calls onSave with null id on first save and stores returned id',
        () async {
      body = 'hello world';
      makeController();
      controller.start();
      await controller.save();
      expect(store.callCount, 1);
      expect(controller.savedId, isNotNull);
      expect(controller.savedId, store.id);
    });

    test('passes existing id on subsequent calls', () async {
      body = 'first';
      makeController();
      controller.start();
      await controller.save();
      final id = controller.savedId!;

      body = 'updated';
      await controller.save();

      expect(store.callCount, 2);
      // The fake store returns the same id both times.
      expect(controller.savedId, id);
    });

    test('uses initialId to update an existing record', () async {
      body = 'new content';
      makeController(initialId: 'existing');
      controller.start();
      await controller.save();

      expect(store.callCount, 1);
      expect(controller.savedId, 'existing');
    });
  });

  group('AutoSaveController.flush', () {
    test('saves immediately and cancels pending debounce', () async {
      body = 'flush test';
      makeController();
      controller.start();

      controller.notifyChanged();
      await controller.flush();

      expect(store.callCount, 1);
      expect(store.body, 'flush test');

      await Future<void>.delayed(_debounceWait);
      // No second call should have fired.
      expect(store.callCount, 1);
    });
  });

  group('AutoSaveController.notifyChanged debounce', () {
    test('saves after debounce delay elapses', () async {
      body = 'debounced save';
      makeController();
      controller.start();

      controller.notifyChanged();
      await Future<void>.delayed(_debounceWait);

      expect(store.callCount, 1);
      expect(store.body, 'debounced save');
    });

    test('multiple rapid calls only trigger one save', () async {
      body = 'rapid';
      makeController();
      controller.start();

      for (var i = 0; i < 5; i++) {
        controller.notifyChanged();
        await Future<void>.delayed(Duration(milliseconds: 5));
      }
      await Future<void>.delayed(_debounceWait);

      expect(store.callCount, 1);
    });
  });

  group('AutoSaveController periodic timer', () {
    test('saves once per interval', () async {
      body = 'periodic content';
      makeController();
      controller.start();

      await Future<void>.delayed(_periodicWait);

      expect(store.callCount, greaterThanOrEqualTo(1));
      expect(store.body, 'periodic content');
    });
  });

  group('AutoSaveController.resetForQuki', () {
    test('subsequent save uses the new target id', () async {
      body = 'new content';
      makeController();
      controller.start();

      controller.resetForQuki(id: 'existing-quki');
      await controller.save();

      expect(store.callCount, 1);
      expect(controller.savedId, 'existing-quki');
    });

    test('resetForQuki to null causes next save to pass null id', () async {
      body = 'first quki';
      makeController();
      controller.start();
      await controller.save();
      expect(controller.savedId, isNotNull);

      controller.resetForQuki(id: null);
      body = 'second quki';
      await controller.save();

      // The second call was passed null, which the fake turns into a new id.
      expect(store.callCount, 2);
    });
  });

  group('AutoSaveController exception handling', () {
    test(
        'save does not throw when onSave raises — regression: silent data loss',
        () async {
      final logged = <LogRecord>[];
      final sub = Logger('AutoSaveController').onRecord.listen(logged.add);
      addTearDown(sub.cancel);

      makeController();
      store.shouldThrow = true;
      body = 'hello';

      await expectLater(controller.save(), completes);

      expect(logged, isNotEmpty);
      expect(logged.first.level, Level.SEVERE);
    });
  });
}
