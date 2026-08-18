const sensitiveFeedbackParameterMarkers = [
  'token',
  'code',
  'auth',
  'key',
  'password',
  'secret',
] as const;

const isSensitiveFeedbackParameter = (name: string) => {
  const normalizedName = name.toLowerCase().replace(/[-_]/g, '');
  return sensitiveFeedbackParameterMarkers.some((marker) => normalizedName.includes(marker));
};

const removeSensitiveParameters = (parameters: URLSearchParams) => {
  for (const name of [...parameters.keys()]) {
    if (isSensitiveFeedbackParameter(name)) parameters.delete(name);
  }
};

const sanitizeHash = (hash: string) => {
  const queryIndex = hash.indexOf('?');
  if (queryIndex < 0) return hash;

  const prefix = hash.slice(0, queryIndex);
  const parameters = new URLSearchParams(hash.slice(queryIndex + 1));
  removeSensitiveParameters(parameters);
  const query = parameters.toString();
  return query ? `${prefix}?${query}` : prefix;
};

export function sanitizeFeedbackLocation(value: string) {
  const url = new URL(value);
  removeSensitiveParameters(url.searchParams);
  url.hash = sanitizeHash(url.hash);
  return url.toString();
}
