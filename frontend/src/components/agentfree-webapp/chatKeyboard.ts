type KeyboardLikeEvent = {
  nativeEvent?: {
    isComposing?: boolean
    keyCode?: number
  }
  keyCode?: number
  which?: number
}

export function isImeComposing(event: KeyboardLikeEvent, trackedComposing = false) {
  const native = event.nativeEvent
  return Boolean(
    trackedComposing
    || native?.isComposing
    || native?.keyCode === 229
    || event.keyCode === 229
    || event.which === 229,
  )
}
