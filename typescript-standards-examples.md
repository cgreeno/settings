Key requirements from our standards:
- Use `fetch()` for HTTP requests with proper typing
- Handle errors with try/catch and typed error handling
- Use discriminated unions for different result types
- Apply `readonly` for immutability where appropriate
- Use utility types like `Pick<>` when beneficial
- Type external API responses properly

#### TypeScript Requirements
- Use TypeScript for all analyzer files
- Simple, clear interfaces
- Minimal type complexity
- Direct JSON parsing with `JSON.parse(fs.readFileSync())`

#### API Calls
- Use `fetch()` for all HTTP requests (following typescript-standards-examples.md)
- Simple error handling with try/catch
- No complex HTTP libraries
- Direct API response parsing with proper typing

#### Error Handling
- Simple try/catch blocks
- Return meaningful error messages
- Graceful degradation when APIs fail
- Follow error handling patterns from typescript-standards-examples.md

#### Data Processing
- Parse JSON directly with `JSON.parse()`
- Use simple array methods (map, filter, forEach)
- No complex data transformation libraries
- Direct property access on JSON objects

### Example Implementation

## 1) Async `fetch` with typing + safe errors

```ts
// Return typed JSON with error handling
async function getUser(id: string): Promise<{ id: string; name: string }> {
  const res = await fetch(`/api/users/${id}`);
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return (await res.json()) as { id: string; name: string };
}
```

---

## 2) Generics for reusable functions

```ts
// Generic identity function
function wrap<T>(value: T): { readonly data: T } {
  return { data: value };
}
```

---

## 3) Narrowing with `in`, `typeof`, `instanceof`

```ts
type Item = { id: string } | { slug: string };

function getKey(x: Item): string {
  return 'id' in x ? x.id : x.slug;
}

function isNumber(x: unknown): x is number {
  return typeof x === 'number';
}

class AppError extends Error {}
function isAppError(e: unknown): e is AppError {
  return e instanceof AppError;
}
```

---

## 4) Discriminated unions

```ts
type Result = { kind: 'ok'; value: number } | { kind: 'err'; message: string };

function handle(r: Result): string {
  switch (r.kind) {
    case 'ok': return `Value: ${r.value}`;
    case 'err': return `Error: ${r.message}`;
  }
}
```

---

## 5) Modules & imports

```ts
// math.ts
export function add(a: number, b: number): number { return a + b; }

// app.ts
import { add } from './math';
console.log(add(2, 3));
```
---

## 6) Immutability with `readonly`

```ts
interface User {
  readonly id: string;
  readonly tags: readonly string[];
}
```

---

## 7) Utility types

```ts
type User = { id: string; name: string; age: number };
type UserPreview = Pick<User, 'id' | 'name'>;
```

---

## 8) Error handling in promises

```ts
async function safe(): Promise<void> {
  try {
    await fetch('/bad-url');
  } catch (e: unknown) {
    console.error('Request failed', e);
  }
}
```

---

## 9) External API client (typed)

```ts
interface Repo { id: number; name: string; }

async function getRepos(user: string): Promise<Repo[]> {
  const res = await fetch(`https://api.github.com/users/${user}/repos`);
  return (await res.json()) as Repo[];
}
```

---

## 10) `fetch` with zod validation

```ts
import { z } from 'zod';

const Repo = z.object({ id: z.number(), name: z.string() });
type Repo = z.infer<typeof Repo>;

async function getRepo(id: number): Promise<Repo> {
  const data = await fetch(`/api/repos/${id}`).then(r => r.json());
  return Repo.parse(data);
}
```
### Testing Requirements

#### Unit/Business Logic Tests (Mock data allowed for API CALLS)
```typescript
// analyzers/tests/license-analyzer.test.ts
import { LicenseAnalyzer } from '../license-analyzer';

// Mock fetch for unit tests
global.fetch = jest.fn();

describe('LicenseAnalyzer', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('should extract license from artifact', () => {
    const artifact = { licenses: [{ value: 'MIT' }] };
    const result = analyzer.extractLicense(artifact);
    expect(result).toBe('MIT');
  });

  test('should fetch license from GitHub API', async () => {
    (fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ license: { spdx_id: 'MIT' } })
    });

    const result = await analyzer.fetchLicenseFromGitHub('pkg:npm/axios@1.0.0');
    expect(result).toBe('MIT');
  });
});
```

#### Integration Tests (NO mock data)
```typescript
// playground/example-test.ts
//NO MOCK DATA
import { LicenseAnalyzer } from '../src/analyzers/license-analyzer';

describe('LicenseAnalyzer Integration', () => {
  test('should analyze real SBOM file', async () => {
    const analyzer = new LicenseAnalyzer();
    const result = await analyzer.analyze('../sbom.json');

    expect(result.totalPackages).toBeGreaterThan(0);
    expect(result.licenses).toBeDefined();

    console.log(`Found ${result.totalPackages} packages`);
    console.log(`Licenses: ${Object.keys(result.licenses)}`);
  });

  test('should make real API calls', async () => {
    const analyzer = new LicenseAnalyzer();
    // This makes actual HTTP requests - no mocking
    const license = await analyzer.fetchLicenseFromGitHub('pkg:npm/lodash@4.17.21');
    expect(typeof license === 'string' || license === null).toBe(true);
  });
});
```
