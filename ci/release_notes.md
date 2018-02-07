# Improvements

- Removed a speculative `blueprint` hook that was latent until
  Genesis 2.5.0 was released.  The hook itself didn't match up to
  what we utimately implemented in Genesis, and was causing issues
  with people running Genesis 2.5.x.  This hook is no longer
  bothering anyone, any more, so you can safely upgrade to 2.5.0
