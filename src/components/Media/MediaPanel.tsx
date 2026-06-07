import { VideoPlayer } from "./VideoPlayer";
import { Transport } from "./Transport";

// Video preview + transport, filling its dock panel.
export function MediaPanel() {
  return (
    <div className="flex h-full w-full flex-col bg-black">
      <div className="min-h-0 flex-1">
        <VideoPlayer />
      </div>
      <Transport />
    </div>
  );
}
