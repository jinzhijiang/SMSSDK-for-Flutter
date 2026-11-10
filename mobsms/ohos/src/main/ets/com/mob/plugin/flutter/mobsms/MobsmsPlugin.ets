import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { BusinessError } from '@kit.BasicServicesKit';
import { ZztSDK } from '@zztsdk/zztcore';
import { CountryEntity, SmsSDK } from '@zztsdk/smshos';

const CHANNEL = 'com.mob.smssdk.channel';
const KEY_RET = 'ret';
const KEY_ERR = 'err';
const KEY_CODE = 'code';
const KEY_MSG = 'msg';
const KEY_STATUS = 'status';
const KEY_VERSION = 'version';
const KEY_COUNTRIES = 'countries';
const KEY_ZONE = 'zone';
const KEY_RULE = 'rule';
const ARG_PHONE_NUMBER = 'phoneNumber';
const ARG_TEMP_CODE = 'tempCode';
const ARG_ZONE = 'zone';
const ARG_CODE = 'code';
const BRIDGE_ERR = 700;
const ERROR_INTERNAL = 'Flutter bridge internal error: ';

/**
 * 与 android 的 onSuccess 对齐：{ ret: {...} }。
 * 必须是 ES Map，Dart 侧用 `response is Map` 判定成功。
 */
function successResponse(ret: Map<string, Object>): Map<string, Object> {
  const response: Map<string, Object> = new Map<string, Object>();
  response.set(KEY_RET, ret);
  return response;
}

/**
 * 与 android 的 onSdkError / onInternalError 对齐：{ err: { code, msg } }。
 * 嵌套层同样是 ES Map。
 */
function errorResponse(code: number, msg: string): Map<string, Object> {
  const err: Map<string, Object> = new Map<string, Object>();
  err.set(KEY_CODE, code);
  err.set(KEY_MSG, msg);
  const response: Map<string, Object> = new Map<string, Object>();
  response.set(KEY_ERR, err);
  return response;
}

function bridgeError(method: string, reason: string): Map<string, Object> {
  return errorResponse(BRIDGE_ERR, ERROR_INTERNAL + method + ': ' + reason);
}

function sdkError(e: BusinessError): Map<string, Object> {
  const code: number = e.code;
  const message: string = e.message;
  const msg: string = message.length > 0 ? message : `${code}`;
  return errorResponse(code, msg);
}

/**
 * mobsms 的鸿蒙实现。
 *
 * AppKey / secret 由 MobPushService 经 @zztsdk/zztcore 初始化，本插件不初始化 SDK，
 * 避免用空 secret 覆盖已经初始化过的进程级配置。
 */
export default class MobsmsPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'MobsmsPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      // getVersion 与 enableWarn 不依赖 SDK 初始化状态
      if (call.method === 'getVersion') {
        const ret: Map<string, Object> = new Map<string, Object>();
        ret.set(KEY_VERSION, SmsSDK.getVersion());
        result.success(successResponse(ret));
        return;
      }
      if (call.method === 'enableWarn') {
        result.success(successResponse(new Map<string, Object>()));
        return;
      }
      if (!MobsmsPlugin.isSdkInitialized()) {
        result.success(bridgeError(call.method, 'Mob SDK is not initialized'));
        return;
      }
      switch (call.method) {
        case 'uploadPrivacyStatus':
          this.uploadPrivacyStatus(call, result);
          break;
        case 'getTextCode':
          await this.getTextCode(call, result);
          break;
        case 'commitCode':
          await this.commitCode(call, result);
          break;
        case 'getSupportedCountries':
          await this.getSupportedCountries(result);
          break;
        case 'getVoiceCode':
        case 'getFriends':
        case 'submitUserInfo':
          // 鸿蒙侧本期不实现，按 D4 用 result.success 回 700，不用 notImplemented
          result.success(bridgeError(call.method, 'not implemented on ohos'));
          break;
        default:
          result.success(bridgeError(call.method, 'unknown method'));
          break;
      }
    } catch (err) {
      result.success(bridgeError(call.method, `${err}`));
    }
  }

  private static isSdkInitialized(): boolean {
    const context = ZztSDK.getContext();
    if (!context) {
      return false;
    }
    const appKey = ZztSDK.getAppKey();
    return appKey !== null && appKey.length > 0;
  }

  private uploadPrivacyStatus(call: MethodCall, result: MethodResult): void {
    const status: boolean = call.argument(KEY_STATUS) as boolean;
    ZztSDK.submitPolicyGrantResult(status);
    result.success(successResponse(new Map<string, Object>()));
  }

  private async getTextCode(call: MethodCall, result: MethodResult): Promise<void> {
    const zone: string = call.argument(ARG_ZONE) as string;
    const phoneNumber: string = call.argument(ARG_PHONE_NUMBER) as string;
    const tempCode: string = call.argument(ARG_TEMP_CODE) as string;
    try {
      const sent: boolean = await SmsSDK.getVerificationCode(zone, phoneNumber, tempCode);
      if (sent) {
        result.success(successResponse(new Map<string, Object>()));
      } else {
        result.success(bridgeError('getTextCode', 'getVerificationCode returned false'));
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      result.success(sdkError(e));
    }
  }

  private async commitCode(call: MethodCall, result: MethodResult): Promise<void> {
    const zone: string = call.argument(ARG_ZONE) as string;
    const phoneNumber: string = call.argument(ARG_PHONE_NUMBER) as string;
    const code: string = call.argument(ARG_CODE) as string;
    try {
      const verified: boolean = await SmsSDK.submitVerificationCode(zone, phoneNumber, code);
      if (verified) {
        result.success(successResponse(new Map<string, Object>()));
      } else {
        result.success(bridgeError('commitCode', 'submitVerificationCode returned false'));
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      result.success(sdkError(e));
    }
  }

  private async getSupportedCountries(result: MethodResult): Promise<void> {
    try {
      const list: CountryEntity[] = await SmsSDK.getSupportedCountries();
      const countries: Array<Object> = [];
      for (let i = 0; i < list.length; i++) {
        const item: CountryEntity = list[i];
        const country: Map<string, Object> = new Map<string, Object>();
        country.set(KEY_ZONE, item.zone);
        country.set(KEY_RULE, item.rule);
        countries.push(country);
      }
      const ret: Map<string, Object> = new Map<string, Object>();
      ret.set(KEY_COUNTRIES, countries);
      result.success(successResponse(ret));
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      result.success(sdkError(e));
    }
  }
}
