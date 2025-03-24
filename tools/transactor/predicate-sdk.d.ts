// Type definitions for @predicate/predicate-sdk
import { PredicateRequest, PredicateResponse } from './types';

declare module '@predicate/predicate-sdk' {
  export interface PredicateClient {
    verify(request: PredicateRequest): Promise<PredicateResponse>;
  }

  export interface PredicateClientOptions {
    apiUrl: string;
    apiKey: string;
  }

  export class PredicateClient {
    constructor(options: PredicateClientOptions);
    verify(request: PredicateRequest): Promise<PredicateResponse>;
  }
} 