// A stand-in for the node agent of istio-cni, for a lab without Kubernetes.
//
// It listens on the ztunnel socket (INPOD_UDS) and hands ztunnel the network
// namespace of every pod listed in a pods file, one line per pod:
//
//     <uid> <netns name> <namespace> <pod name> <service account>
//
// It reads the file again every 300 ms: a new line enrolls a pod, a removed
// line takes it out. When ztunnel restarts, the agent waits for the new
// ztunnel and sends it every pod again, as istio-cni does.
//
// Usage: INPOD_UDS=/var/run/ztunnel/ztunnel.sock nodeagent <pods file>

use std::collections::BTreeMap;
use std::fs::File;
use std::time::Duration;

use tokio::io::AsyncReadExt;
use ztunnel::inpod::istio::zds::WorkloadInfo;
use ztunnel::inpod::test_helpers::{
    read_hello, read_msg, send_snap_sent, send_workload_added, send_workload_del,
};
use ztunnel::inpod::WorkloadUid;

#[derive(Clone, PartialEq)]
struct Pod {
    netns: String,
    info: WorkloadInfo,
}

fn read_pods(path: &str) -> BTreeMap<String, Pod> {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    let mut pods = BTreeMap::new();
    for line in text.lines() {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() != 5 || f[0].starts_with('#') {
            continue;
        }
        pods.insert(
            f[0].to_string(),
            Pod {
                netns: f[1].to_string(),
                info: WorkloadInfo {
                    namespace: f[2].to_string(),
                    name: f[3].to_string(),
                    service_account: f[4].to_string(),
                },
            },
        );
    }
    pods
}

#[tokio::main]
async fn main() {
    let uds = std::env::var("INPOD_UDS").expect("set INPOD_UDS");
    let path = std::env::args().nth(1).expect("usage: nodeagent <pods file>");
    let _ = std::fs::remove_file(&uds);
    let listener =
        ztunnel::inpod::packet::bind(std::path::Path::new(&uds)).expect("bind");

    loop {
        println!("nodeagent: waiting for ztunnel on {uds}");
        let (mut sock, _) = listener.accept().await.expect("accept");
        let hello = read_hello(&mut sock).await;
        println!("nodeagent: ztunnel connected, protocol {:?}", hello.version);

        // Send the pods that exist now, then the end of the snapshot.
        let mut sent: BTreeMap<String, Pod> = BTreeMap::new();
        let mut alive = true;
        for (uid, pod) in read_pods(&path) {
            if !add(&mut sock, &uid, &pod).await {
                alive = false;
                break;
            }
            sent.insert(uid, pod);
        }
        if alive {
            send_snap_sent(&mut sock).await;
            let _ = read_msg(&mut sock).await;
            println!("nodeagent: snapshot sent, {} pods", sent.len());
        }

        // Follow the pods file until ztunnel goes away.
        while alive {
            tokio::time::sleep(Duration::from_millis(300)).await;
            let want = read_pods(&path);
            for uid in sent.keys().cloned().collect::<Vec<_>>() {
                if want.get(&uid) != sent.get(&uid) {
                    let wl = WorkloadUid::new(uid.clone());
                    send_workload_del(&mut sock, wl).await;
                    let _ = read_msg(&mut sock).await;
                    println!("nodeagent: removed {uid}");
                    sent.remove(&uid);
                }
            }
            for (uid, pod) in want {
                if !sent.contains_key(&uid) {
                    if !add(&mut sock, &uid, &pod).await {
                        alive = false;
                        break;
                    }
                    sent.insert(uid, pod);
                }
            }
            // A closed socket reads zero bytes without blocking.
            let mut probe = [0u8; 1];
            let read = sock.read(&mut probe);
            let wait = Duration::from_millis(1);
            if let Ok(Ok(0)) = tokio::time::timeout(wait, read).await {
                alive = false;
            }
        }
        println!("nodeagent: ztunnel disconnected");
    }
}

async fn add(sock: &mut tokio::net::UnixStream, uid: &str, pod: &Pod) -> bool {
    let netns = match File::open(format!("/var/run/netns/{}", pod.netns)) {
        Ok(f) => f,
        Err(e) => {
            println!("nodeagent: cannot open netns {}: {e}", pod.netns);
            return true;
        }
    };
    let wl = WorkloadUid::new(uid.to_string());
    send_workload_added(sock, wl, Some(pod.info.clone()), netns).await;
    let resp = read_msg(sock).await;
    println!(
        "nodeagent: added {uid} ({}/{}) -> {:?}",
        pod.info.namespace, pod.info.name, resp.payload
    );
    true
}
