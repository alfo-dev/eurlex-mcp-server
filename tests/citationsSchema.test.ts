import { describe, it, expect } from 'vitest'
import { citationsSchema } from '../src/schemas/citationsSchema.js'

describe('citationsSchema', () => {
  it('C1 – accepts valid CELEX-ID with defaults', () => {
    const result = citationsSchema.parse({ celex_id: '32024R1689' })
    expect(result.celex_id).toBe('32024R1689')
    expect(result.language).toBe('DEU')
    expect(result.direction).toBe('both')
    expect(result.limit).toBe(20)
  })

  it('C2 – accepts direction=cited_by', () => {
    const result = citationsSchema.parse({ celex_id: '32024R1689', direction: 'cited_by' })
    expect(result.direction).toBe('cited_by')
  })

  it('C3 – accepts direction=cites', () => {
    const result = citationsSchema.parse({ celex_id: '32024R1689', direction: 'cites' })
    expect(result.direction).toBe('cites')
  })

  it('C4 – rejects invalid CELEX-ID', () => {
    expect(() => citationsSchema.parse({ celex_id: 'bad' })).toThrow()
  })
})
