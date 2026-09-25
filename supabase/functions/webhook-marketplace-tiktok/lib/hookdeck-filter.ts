function matchField(actual: unknown, expected: unknown): boolean {
  if (expected === null || expected === undefined) {
    return actual === expected;
  }

  if (typeof expected !== "object" || Array.isArray(expected)) {
    return actual === expected;
  }

  const exp = expected as Record<string, unknown>;

  if ("$exist" in exp) {
    const exists = actual !== undefined && actual !== null;
    return exp.$exist ? exists : !exists;
  }

  if ("$neq" in exp) {
    return actual !== exp.$neq;
  }

  if ("$nin" in exp) {
    const nin = exp.$nin;
    if (typeof nin === "string" && typeof actual === "string") {
      return !actual.includes(nin);
    }
    if (Array.isArray(nin)) {
      return !nin.includes(actual);
    }
    return true;
  }

  if ("$in" in exp) {
    const inn = exp.$in;
    if (typeof inn === "string" && typeof actual === "string") {
      return actual.includes(inn);
    }
    if (Array.isArray(inn)) {
      return inn.includes(actual);
    }
    return false;
  }

  if ("$or" in exp) {
    const arr = exp.$or as unknown[];
    return arr.some((value) => actual === value);
  }

  if ("$not" in exp) {
    return !matchField(actual, exp.$not);
  }

  if (typeof actual === "object" && actual !== null && !Array.isArray(actual)) {
    return matchesFilter(actual, expected);
  }

  return actual === expected;
}

export function matchesFilter(data: unknown, filter: unknown): boolean {
  if (filter === null || filter === undefined) {
    return true;
  }

  if (typeof filter !== "object" || Array.isArray(filter)) {
    return data === filter;
  }

  const schema = filter as Record<string, unknown>;

  if ("$and" in schema) {
    const conditions = schema.$and as unknown[];
    return conditions.every((item) => matchesFilter(data, item));
  }

  if ("$or" in schema) {
    const conditions = schema.$or as unknown[];
    return conditions.some((item) => matchesFilter(data, item));
  }

  if ("$not" in schema) {
    return !matchesFilter(data, schema.$not);
  }

  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    return false;
  }

  const record = data as Record<string, unknown>;

  for (const [key, expected] of Object.entries(schema)) {
    if (!matchField(record[key], expected)) {
      return false;
    }
  }

  return true;
}
