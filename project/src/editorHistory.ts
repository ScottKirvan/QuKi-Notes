import { history } from "@codemirror/commands";
import { Compartment, type Extension, type TransactionSpec } from "@codemirror/state";

const historyCompartment = new Compartment();

export const resettableHistory: Extension = historyCompartment.of(history());

/**
 * The transactions that replace the whole document with `body` and leave
 * nothing to undo or redo, for loading a different QuKi into the editor.
 * Undo history belongs to one QuKi: kept across a load, undo would put the
 * previous QuKi's text into this one, and auto-save would then write it.
 * Dropping the history extension and adding it back is what discards its
 * stored events; dispatch the returned specs in order.
 */
export function replaceDocumentAndForgetHistory(body: string, docLength: number): TransactionSpec[] {
  return [
    {
      changes: { from: 0, to: docLength, insert: body },
      selection: { anchor: 0 },
      effects: historyCompartment.reconfigure([]),
    },
    { effects: historyCompartment.reconfigure(history()) },
  ];
}
