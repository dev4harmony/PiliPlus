import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

/**
 * Application-wide audio policy for mpv/OHAudio streams (API 12+).
 * Keep a single owned listener and acknowledge both success and failure. The
 * audio_session fork neither deactivates its native session nor catches rejected
 * activation promises, and adds a new listener on every activation.
 */
export default class HarmonyAudioSession implements FlutterPlugin {
  private channel: MethodChannel | null = null;
  private manager: audio.AudioSessionManager | null = null;
  private listening: boolean = false;
  private pending: Promise<void> = Promise.resolve();

  private onDeactivated = (event: audio.AudioSessionDeactivatedEvent): void => {
    this.channel?.invokeMethod('onDeactivated', event.reason);
  };

  getUniqueClassName(): string {
    return 'HarmonyAudioSession';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'pili/audio_session');
    this.channel.setMethodCallHandler(this);
    this.manager = audio.getAudioManager().getSessionManager();
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.stopListening();
    const manager = this.manager;
    this.manager = null;
    // Activation may still be in flight when the engine is detached. Drain it
    // before cleanup so its completion cannot leave an orphaned active session.
    this.pending = this.pending.then(async (): Promise<void> => {
      if (manager?.isAudioSessionActivated()) {
        await manager.deactivateAudioSession();
      }
    }).catch((err: BusinessError) => {
      console.error(`HarmonyAudioSession cleanup failed: ${err.code} ${err.message}`);
    });
  }

  private stopListening(): void {
    if (this.listening) {
      this.manager?.off('audioSessionDeactivated', this.onDeactivated);
      this.listening = false;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'setActive') {
      result.notImplemented();
      return;
    }
    // A rapid play/pause must not let an older activation finish after a pause.
    this.pending = this.pending.then(() => this.setActive(call, result));
  }

  private async setActive(call: MethodCall, result: MethodResult): Promise<void> {
    const manager = this.manager;
    if (manager === null) {
      result.error('audio_session_unavailable', 'Audio session is not attached', null);
      return;
    }
    const active: boolean = call.argument('active') ?? false;
    const mixWithOthers: boolean = call.argument('mixWithOthers') ?? false;
    try {
      if (active) {
        if (!this.listening) {
          manager.on('audioSessionDeactivated', this.onDeactivated);
          this.listening = true;
        }
        // Do not opt out of the system's mandatory interruptions (e.g. calls).
        const strategy: audio.AudioSessionStrategy = {
          concurrencyMode: mixWithOthers
            ? audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
            : audio.AudioConcurrencyMode.CONCURRENCY_PAUSE_OTHERS,
        };
        await manager.activateAudioSession(strategy);
      } else {
        if (manager.isAudioSessionActivated()) {
          await manager.deactivateAudioSession();
        }
        this.stopListening();
      }
      result.success(true);
    } catch (err) {
      const error = err as BusinessError;
      result.error('audio_session_error', `${error.code}: ${error.message}`, null);
    }
  }
}
