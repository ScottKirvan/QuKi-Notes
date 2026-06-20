import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

void main() {
  group('BlockSplitter.split', () {
    test('empty string returns single empty block', () {
      expect(BlockSplitter.split(''), ['']);
    });

    test('single line is one block', () {
      expect(BlockSplitter.split('hello world'), ['hello world']);
    });

    test('two lines produce two blocks', () {
      expect(BlockSplitter.split('first\nsecond'), ['first', 'second']);
    });

    test('blank line produces an empty-string block', () {
      expect(BlockSplitter.split('one\n\ntwo'), ['one', '', 'two']);
    });

    test('three lines produce three blocks', () {
      expect(BlockSplitter.split('one\ntwo\nthree'), ['one', 'two', 'three']);
    });

    test('heading is its own block with no special treatment needed', () {
      expect(
        BlockSplitter.split('some text\n# Heading'),
        ['some text', '# Heading'],
      );
    });

    test('list items are separate blocks', () {
      expect(BlockSplitter.split('- a\n- b\n- c'), ['- a', '- b', '- c']);
    });

    test('task list items are separate blocks', () {
      expect(
        BlockSplitter.split('- [ ] task one\n- [x] task two'),
        ['- [ ] task one', '- [x] task two'],
      );
    });

    test('ordered list items are separate blocks', () {
      expect(
        BlockSplitter.split('1. first\n2. second'),
        ['1. first', '2. second'],
      );
    });

    test('trailing newline produces trailing empty block', () {
      expect(BlockSplitter.split('hello\n'), ['hello', '']);
    });
  });

  group('BlockSplitter.join', () {
    test('single block returns that block unchanged', () {
      expect(BlockSplitter.join(['hello']), 'hello');
    });

    test('two blocks joined with single newline', () {
      expect(BlockSplitter.join(['first', 'second']), 'first\nsecond');
    });

    test('empty list produces empty string', () {
      expect(BlockSplitter.join([]), '');
    });

    test('empty block in list produces blank line', () {
      expect(BlockSplitter.join(['one', '', 'two']), 'one\n\ntwo');
    });
  });

  group('BlockSplitter round-trip', () {
    void roundTrip(String markdown) {
      expect(
        BlockSplitter.join(BlockSplitter.split(markdown)),
        markdown,
        reason: 'round-trip failed for: ${markdown.replaceAll('\n', '\\n')}',
      );
    }

    test('single line', () => roundTrip('hello world'));
    test('two paragraphs separated by blank line', () => roundTrip('one\n\ntwo'));
    test('heading only', () => roundTrip('# My Heading'));
    test('heading and paragraph on consecutive lines',
        () => roundTrip('# Title\nparagraph'));
    test('heading blank-line paragraph', () => roundTrip('# Title\n\nbody text'));
    test('unordered list items', () => roundTrip('- a\n- b\n- c'));
    test('ordered list items', () => roundTrip('1. first\n2. second'));
    test('task list items', () => roundTrip('- [ ] todo\n- [x] done'));
    test('mixed content', () {
      roundTrip('# Title\n\nParagraph text.\n\n- list item\n- another');
    });
  });

  group('BlockSplitter.listContinuation', () {
    test('returns null for plain text', () {
      expect(BlockSplitter.listContinuation('hello'), isNull);
    });

    test('returns "- " for unordered list item', () {
      expect(BlockSplitter.listContinuation('- item'), '- ');
    });

    test('returns "* " for asterisk list item', () {
      expect(BlockSplitter.listContinuation('* item'), '* ');
    });

    test('returns "- [ ] " for unchecked task', () {
      expect(BlockSplitter.listContinuation('- [ ] task'), '- [ ] ');
    });

    test('returns "- [ ] " for checked task (resets to unchecked)', () {
      expect(BlockSplitter.listContinuation('- [x] done'), '- [ ] ');
    });

    test('increments ordered list number', () {
      expect(BlockSplitter.listContinuation('1. first'), '2. ');
      expect(BlockSplitter.listContinuation('5. fifth'), '6. ');
    });
  });
}
