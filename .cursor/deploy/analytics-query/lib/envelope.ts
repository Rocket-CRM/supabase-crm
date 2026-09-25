export function successEnvelope<T>(
  data: T,
  _meta?: unknown,
) {
  return {
    success: true as const,
    title: null as string | null,
    description: null as string | null,
    data,
  }
}

export function errorEnvelope(
  title: string,
  description: string | null = null,
  code?: string,
) {
  return {
    success: false as const,
    title,
    description,
    data: null,
    ...(code ? { code } : {}),
  }
}
