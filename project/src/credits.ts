import creditsJson from "./credits.json";

export interface CreditEntry {
  name: string;
  detail?: string;
  url?: string;
}

export interface CreditSection {
  title: string;
  entries: CreditEntry[];
}

export interface CreditsData {
  sections: CreditSection[];
  notice: string;
}

export const creditsData: CreditsData = creditsJson;
