//
//  ViewController.m
//  MQTT
//
//  Created by txooo on 2018/3/5.
//  Copyright © 2018年 iBo. All rights reserved.
//
/*
 问题一
 无论是什么情况的断开,
 MQTTSession的代理方法
 
 -(void)handleEvent:(MQTTSession *)session event:(MQTTSessionEvent)eventCode error:(NSError *)error;
 1
 都会返回closed这样的错误码
 这时候只需要执行重新连接即可
 - (void)connect{
 [_mqttSession connect];
 }
 
 但是稍微注意的是,最好手工控制一下重连的延迟时间,不然在处于断网的情况下,mqtt会不断重连,不断回调错误码,然后又崩溃风险,加一下延迟执行重连,目前没有发现崩溃可能.
 问题二
 iOS系统,在mqtt进入后台以后,MQTT好像就不工作了,回调什么的也没有,只能重新打开app以后,才会执行回调,才能重新连接,不知道大家有没有好点的办法解决,先记录一下, 等找到办法了再补充
 
 问题三(诡异的线程卡顿)
 1.切换为4G网络后,登录App同时登陆MQTT,在订阅消息的时候线程卡主!!!!!
 明确一个事实:
 
 在订阅消息时,必须在主线程,否则不会回调获取消息
 网络情况不好时,就容易在订阅消息这一步卡主主线程,导致UI线程卡顿.
 dispatch_async(dispatch_get_main_queue(), ^{
 // [self.mqttSession subscribeTopic:_topic];
    [self.mqttSession subscribeToTopic:_topic atLevel:MQTTQosLevelAtLeastOnce];
 });
 解决办法就是超时时间设置小一点就好!!!!!!!!
 [self.mqttSession connectAndWaitTimeout:1];
 
 补充一个坑
 使用MQTTClient的SDK时,为了离线能获取未推送的消息, 我设置了
 clean:false ,结果导致App挂起一段时间后,使用同样的clientID再去获取推送时, (App重新唤起,重新连接,但就是收不到推送).
 设置clean:true 则问题解决.
 
 不知是否后端配置的代码是否存在问题,如果收不到推送,可以先尝试clean掉session.方便排除问题
 补充第二个坑
 App多次退出登录 再登陆以后, MQTT推送的回调回调多次
 
 2018-01-26 17:46:43.636585+0800 sandbao[3917:1696336] [MQTTSession] checkDup f974c1662eed04a4066deb33c61cca12 @1516960004
 后来的解决办法是
 
 关闭MQTT
- (void)closeMQTT{
    
    //避免删除kvo异常
    @try{
        //清除kvo监听
        [self.manager removeObserver:self forKeyPath:@"state"];
    }
    @catch(NSException *exception){
        
    }
    
    //关闭连接 - 触发监听(有可能关成功,测试出有关失败的可能)
    [self.manager disconnect];
    
}
 
 在关闭MQTT连接的时候,不要clean掉 self.manager = nil;
 而是在App重新连接的时候, 替换session的clientID
 self.manager.session.clientId = clientID;
 [self.manager connectToLast];
 
 查看 MQTTSession.m
 在 执行 [self.manager connectToLast];方法后,
 最终会执行到以下方法,
 
 - (void)connect {
 
 if (MQTTStrict.strict &&
 self.clientId && self.clientId.length < 1 &&
 !self.cleanSessionFlag) {
 NSException* myException = [NSException
 exceptionWithName:@"clientId must be at least 1 character long if cleanSessionFlag is off"
 reason:[NSString stringWithFormat:@"clientId length = %lu",
 (unsigned long)[self.clientId dataUsingEncoding:NSUTF8StringEncoding].length]
 userInfo:nil];
 @throw myException;
 }
 ....
 self.transport.delegate = self;
 [self.transport open];
 }
 所以,在这个方法执行之前 切换其 self.clientID 即可重新连接,并不需要每次都重新登录.
 
 注意 - MQTTClient更新以后 connect方法由变化
 新方法增加了几个参数,应该是支持 配置安全策略 / 证书 /MQTTSSLSecurityPolicy
 具体参考这篇文章 (iOS)MQTT连接 遗嘱 双向认证 https://www.jianshu.com/p/4676834ac3c4
 
 [self.manager
 connectTo:kIP
 port:kPort
 tls:false
 keepalive:30
 clean:true
 auth:true
 user:kMqttuserNmae
 pass:kMqttpasswd
 will:false
 willTopic:@""
 willMsg:nil
 willQos:MQTTQosLevelExactlyOnce
 willRetainFlag:false
 withClientId:clientID
 securityPolicy:nil
 certificates:nil
 protocolLevel:MQTTProtocolVersion0
 connectHandler:^(NSError *error) {
 
 }];
 */

#import "ViewController.h"
#import <MQTTClient/MQTTClient.h>
#import <MQTTClient/MQTTLog.h>

//建议使用后者维持静态资源,而且已经封装好自动重连等逻辑
#import <MQTTClient/MQTTSessionManager.h>


@interface ViewController ()<MQTTSessionDelegate,MQTTSessionManagerDelegate>
{
    MQTTSession *_session;
    MQTTSessionManager *_manager;
    UITextView *_textView;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:@"sendMsg" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(send:) forControlEvents:UIControlEventTouchUpInside];
    [button setBackgroundColor:[UIColor greenColor]];
    button.frame = CGRectMake(100, 100, 150, 50);
    [self.view addSubview:button];
    
    UIButton *clearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [clearButton setTitle:@"Clear" forState:UIControlStateNormal];
    [clearButton addTarget:self action:@selector(clearMsg) forControlEvents:UIControlEventTouchUpInside];
    [clearButton setBackgroundColor:[UIColor greenColor]];
    clearButton.frame = CGRectMake(260, 100, 60, 30);
    [self.view addSubview:clearButton];
    
    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 180, self.view.frame.size.width - 40, CGRectGetHeight(self.view.bounds) - 200)];
    textView.backgroundColor = [UIColor yellowColor];
    textView.editable = NO;
    [self.view addSubview:textView];
    _textView = textView;
#if 0
    MQTTCFSocketTransport *transport = [[MQTTCFSocketTransport alloc] init];
    transport.host = @"iot.eclipse.org";
    transport.port = 1883;
    
    MQTTSession *session = [[MQTTSession alloc] init];
    session.transport = transport;
    session.clientId = @"ExampleAndroidClient";

    
    session.delegate = self;
    
    [session connectAndWaitTimeout:1]; //this is part of the synchronous API
    
    _session = session;
    
    [session setUserName:@""];
    [session setPassword:@""];
    
    
    [session subscribeToTopic:@"MQTTExample/Message" atLevel:MQTTQosLevelExactlyOnce subscribeHandler:^(NSError *error, NSArray<NSNumber *> *gQoss){
        if (error) {
            DDLogWarn(@"Subscription failed %@", error.localizedDescription);
        } else {
            DDLogInfo(@"Subscription sucessfull! Granted Qos: %@", gQoss);
        }
    }]; // this is part of the block API
    
#else
    MQTTSessionManager *manager = [[MQTTSessionManager alloc]init];
    [manager connectTo:@"iot.eclipse.org" port:1883 tls:NO keepalive:60 clean:false auth:NO user:nil pass:nil willTopic:@"MQTTExample/Message" will:[@"hello world! Disconnect!" dataUsingEncoding:NSUTF8StringEncoding] willQos:MQTTQosLevelExactlyOnce willRetainFlag:YES withClientId:@"ExampleAndroidClient"];
    manager.delegate = self;
    [manager addObserver:self forKeyPath:@"state" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    manager.subscriptions = @{@"MQTTExample/Message":@(MQTTQosLevelExactlyOnce)};
    _manager = manager;
#endif
}

- (void)send:(UIButton *)sender {
    NSData *data = [@"你好!" dataUsingEncoding:NSUTF8StringEncoding];
#if 0
    BOOL result = [_session publishAndWaitData:data onTopic:@"MQTTExample/Message" retain:YES qos:MQTTQosLevelExactlyOnce];
#else
    BOOL result = [_manager.session publishAndWaitData:data onTopic:@"MQTTExample/Message" retain:YES qos:MQTTQosLevelExactlyOnce];
#endif
    DDLogInfo(@"%i",result);
}

- (void)clearMsg {
    _textView.text = @"";
}

#pragma mark MQTTSessionManagerDelegate
- (void)handleMessage:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained {
    DDLogInfo(@"------------->>%@",topic);
    
    NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    DDLogInfo(@"%@",dataString);
    _textView.text = [_textView.text stringByAppendingString:[NSString stringWithFormat:@"\n%@",dataString]];
    [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length, 0)];
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager didChangeState:(MQTTSessionManagerState)newState {
    
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager didDeliverMessage:(UInt16)msgID {
    
}

- (void)sessionManager:(MQTTSessionManager *)sessionManager didReceiveMessage:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained {
    DDLogInfo(@"data::Topic:%@----->%@",topic,[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    switch (_manager.state) {
        case MQTTSessionManagerStateClosed:
            break;
        case MQTTSessionManagerStateClosing:
            break;
        case MQTTSessionManagerStateConnected:
            break;
        case MQTTSessionManagerStateConnecting:
            break;
        case MQTTSessionManagerStateError:
            break;
        case MQTTSessionManagerStateStarting:
        default:
            break;
    }
}

#pragma mark MQTTSessionDelegate

- (void)newMessage:(MQTTSession *)session data:(NSData *)data onTopic:(NSString *)topic qos:(MQTTQosLevel)qos retained:(BOOL)retained mid:(unsigned int)mid {
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    DDLogInfo(@"data::::%@",str);
    _textView.text = [_textView.text stringByAppendingString:[NSString stringWithFormat:@"\n%@",str]];
    [_textView scrollRangeToVisible:NSMakeRange(_textView.text.length, 0)];
}

- (void)session:(MQTTSession *)session newMessage:(NSData *)data onTopic:(NSString *)topic {
    
}

- (BOOL)newMessageWithFeedback:(MQTTSession *)session data:(NSData *)data onTopic:(NSString *)topic qos:(MQTTQosLevel)qos retained:(BOOL)retained mid:(unsigned int)mid {
    return YES;
}

- (void)connected:(MQTTSession *)session {
    
}

- (void)connectionClosed:(MQTTSession *)session {
    
}

- (void)connectionRefused:(MQTTSession *)session error:(NSError *)error {
    
}

- (void)connectionError:(MQTTSession *)session error:(NSError *)error {
    
}

- (void)connected:(MQTTSession *)session sessionPresent:(BOOL)sessionPresent {
    
}

- (void)subAckReceived:(MQTTSession *)session msgID:(UInt16)msgID grantedQoss:(NSArray<NSNumber *> *)qoss {
    
}

- (void)handleEvent:(MQTTSession *)session event:(MQTTSessionEvent)eventCode error:(NSError *)error {
    DDLogWarn(@"错误码:%li---%@",(long)eventCode,error.localizedDescription);
    if (error) {
        if (_session.status != MQTTSessionStatusConnected) {
             [_session connect];
        }
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
