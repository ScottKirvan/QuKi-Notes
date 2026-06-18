import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_live_editor/markdown_live_editor.dart';

void main() {
  group('BlockSplitter.split', () {
    test('empty string returns single empty block', () {
      expect(BlockSplitter.split(''), ['']);
    });

    test('single paragraph with no blank lines is one block', () {
      expect(BlockSplitter.split('hello world'), ['hello world']);
    });

    test('splits on double newline', () {
      expect(
        BlockSplitter.split('first\n\nsecond'),
        ['first', 'second'],
      );
    });

    test('three paragraphs produce three blocks', () {
      expect(
        BlockSplitter.split('one\n\ntwo\n\nthree'),
        ['one', 'two', 'three'],
      );
    });

    test('heading always starts its own block even without blank line', () {
      expect(
        BlockSplitter.split('some text\n# Heading'),
        ['some text', '# Heading'],
      );
    });

    test('heading followed by paragraph is two blocks', () {
      expect(
        BlockSplitter.split('# Title\nparagraph'),
        ['# Title', 'paragraph'],
      );
    });

    test('contiguous unordered list lines are grouped into one block', () {
      expect(
        BlockSplitter.split('- a\n- b\n- c'),
        ['- a\n- b\n- c'],
      );
    });

    test('contiguous list lines separated by blank lines stay one block', () {
      expect(
        BlockSplitter.split('- a\n\n- b'),
        ['- a\n\n- b'],
      );
    });

    test('task list lines are grouped into one block', () {
      expect(
        BlockSplitter.split('- [ ] task one\n- [x] task two'),
        ['- [ ] task one\n- [x] task two'],
      );
    });

    test('ordered list lines are grouped into one block', () {
      expect(
        BlockSplitter.split('1. first\n2. second\n3. third'),
        ['1. first\n2. second\n3. third'],
      );
    });

    test('list followed by paragraph splits into two blocks', () {
      expect(
        BlockSplitter.split('- item\n\nparagraph'),
        ['- item', 'paragraph'],
      );
    });

    test('mixed: heading + paragraph + list', () {
      expect(
        BlockSplitter.split('# Title\n\nparagraph\n\n- item one\n- item two'),
        ['# Title', 'paragraph', '- item one\n- item two'],
      );
    });
  });

  group('BlockSplitter.join', () {
    test('single block returns that block unchanged', () {
      expect(BlockSplitter.join(['hello']), 'hello');
    });

    test('two blocks joined with double newline', () {
      expect(BlockSplitter.join(['first', 'second']), 'first\n\nsecond');
    });

    test('empty list produces empty string', () {
      expect(BlockSplitter.join([]), '');
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

    test('single paragraph', () => roundTrip('hello world'));
    test('two paragraphs', () => roundTrip('one\n\ntwo'));
    test('heading only', () => roundTrip('# My Heading'));
    test('heading + paragraph', () => roundTrip('# Title\n\nbody text'));
    test('unordered list', () => roundTrip('- a\n- b\n- c'));
    test('ordered list', () => roundTrip('1. first\n2. second'));
    test('task list', () => roundTrip('- [ ] todo\n- [x] done'));
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
