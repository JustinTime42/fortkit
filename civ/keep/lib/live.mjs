export function subscribeRefresh(load, reportFailure = console.error) {
  const stream = new EventSource("/events");
  const refresh = () => {
    try {
      void Promise.resolve(load()).catch(reportFailure);
    } catch (error) {
      reportFailure(error);
    }
  };
  stream.addEventListener("tick", refresh);
  stream.addEventListener("sign", refresh);
  addEventListener("pagehide", () => stream.close(), { once: true });
  return stream;
}
