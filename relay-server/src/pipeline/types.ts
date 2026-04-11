export type Priority = 'interrupt' | 'queue' | 'silent';
export type EventCategory = 'question' | 'error' | 'completion' | 'permission' | 'progress';

export interface ClassifiedEvent {
  priority: Priority;
  category: EventCategory;
  rawData: unknown;
}
