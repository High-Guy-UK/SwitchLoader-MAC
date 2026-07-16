declare const screen: {
  width: number;
  height: number;
  getContext(type: "2d"): CanvasRenderingContext2D;
};

declare namespace Switch {
  function mkdirSync(path: string): void;
  function file(path: string): {
    writable: WritableStream<string | BufferSource>;
  };
}
