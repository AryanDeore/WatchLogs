/**
 * Private-window capture needs a fresh, authenticated App response. A missing
 * response fails closed so Extension storage cannot retain an independent opt-in.
 */
export function capturesPrivateWindowsForHello(appResponse) {
  return appResponse?.ok === true && appResponse.capturePrivateWindows === true;
}
