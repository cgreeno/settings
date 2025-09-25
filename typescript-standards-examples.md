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

```typescript
// license-analyzer.ts
export interface LicenseResult {
  totalPackages: number;
  licensedPackages: number;
  unknownPackages: number;
  licenses: Record<string, number>;
  unknownList: string[];
  recommendations: string[];
}

export class LicenseAnalyzer {
  private readonly githubToken?: string;

  constructor() {
    this.githubToken = process.env.GITHUB_TOKEN;
  }

  async analyze(sbomPath: string): Promise<LicenseResult> {
    const sbom = JSON.parse(fs.readFileSync(sbomPath, 'utf8'));
    const results = [];

    for (const artifact of sbom.artifacts) {
      const license = this.extractLicense(artifact);
      if (license) {
        results.push({ name: artifact.name, version: artifact.version, license });
      } else {
        // Make API call for missing license
        const apiLicense = await this.fetchLicenseFromAPI(artifact.purl);
        results.push({
          name: artifact.name,
          version: artifact.version,
          license: apiLicense || 'Unknown'
        });
      }
    }

    return this.createSummary(results);
  }

  private async fetchLicenseFromAPI(purl: string): Promise<string | null> {
    try {
      const response = await fetch(`https://api.github.com/repos/owner/repo/license`);
      if (!response.ok) return null;

      const data = await response.json() as { license: { spdx_id: string } };
      return data.license.spdx_id;
    } catch (error: unknown) {
      console.error('API call failed', error);
      return null;
    }
  }
}
```
