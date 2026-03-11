import { describe, it, expect, vi, beforeEach } from 'vitest'
import { CellarClient } from '../src/services/cellarClient.js'

const mockFetch = vi.fn()

beforeEach(() => {
  mockFetch.mockReset()
  vi.stubGlobal('fetch', mockFetch)
})

describe('buildCitationsQuery()', () => {
  it('C5 – generates SPARQL for "cites" direction with work_cites_work', () => {
    const client = new CellarClient()
    const sparql = client.buildCitationsQuery('32024R1689', 'DEU', 'cites', 20)

    expect(sparql).toContain('32024R1689')
    expect(sparql).toContain('work_cites_work')
  })

  it('C6 – generates SPARQL for "cited_by" direction', () => {
    const client = new CellarClient()
    const sparql = client.buildCitationsQuery('32024R1689', 'DEU', 'cited_by', 20)

    expect(sparql).toContain('32024R1689')
    expect(sparql).toContain('work_cites_work')
  })

  it('C7 – generates UNION query for "both" direction', () => {
    const client = new CellarClient()
    const sparql = client.buildCitationsQuery('32024R1689', 'DEU', 'both', 20)

    expect(sparql).toContain('UNION')
  })

  it('C8 – includes legal basis, amends, and repeals relationships', () => {
    const client = new CellarClient()
    const sparql = client.buildCitationsQuery('32024R1689', 'DEU', 'both', 20)

    expect(sparql).toContain('resource_legal_based_on_resource_legal')
    expect(sparql).toContain('resource_legal_amends_resource_legal')
    expect(sparql).toContain('resource_legal_repeals_resource_legal')
  })
})

describe('citationsQuery()', () => {
  it('C9 – returns CitationsResult with parsed citation entries', async () => {
    const sparqlResponse = {
      results: {
        bindings: [{
          celex: { type: 'literal', value: '32016R0679' },
          title: { type: 'literal', value: 'DSGVO' },
          date: { type: 'literal', value: '2016-04-27' },
          resType: { type: 'literal', value: 'REG' },
          rel: { type: 'literal', value: 'cites' },
        }],
      },
    }

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => sparqlResponse,
    })

    const client = new CellarClient()
    const result = await client.citationsQuery('32024R1689', 'DEU', 'both', 20)

    expect(result.celex_id).toBe('32024R1689')
    expect(result.citations).toHaveLength(1)
    expect(result.citations[0].celex).toBe('32016R0679')
    expect(result.citations[0].relationship).toBe('cites')
  })

  it('C10 – returns empty citations array when no relationships found', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ results: { bindings: [] } }),
    })

    const client = new CellarClient()
    const result = await client.citationsQuery('32024R1689', 'DEU', 'both', 20)

    expect(result.citations).toEqual([])
    expect(result.total).toBe(0)
  })
})
