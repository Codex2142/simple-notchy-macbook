//! Typed in-process event bus for decoupled communication across Project Island modules.

use crate::state_machine::IslandStateSnapshot;
use island_common::RetentionPolicy;
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum DomainEvent {
    StateChanged(IslandStateSnapshot),
    RetentionPolicyUpdated(RetentionPolicy),
    ModuleToggled { module_id: String, enabled: bool },
}

pub type EventSubscriber = Arc<dyn Fn(&DomainEvent) + Send + Sync + 'static>;

#[derive(Default, Clone)]
pub struct EventBus {
    subscribers: Arc<Mutex<Vec<EventSubscriber>>>,
}

impl EventBus {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn subscribe<F>(&self, callback: F)
    where
        F: Fn(&DomainEvent) + Send + Sync + 'static,
    {
        if let Ok(mut subs) = self.subscribers.lock() {
            subs.push(Arc::new(callback));
        }
    }

    pub fn publish(&self, event: &DomainEvent) {
        let callbacks = match self.subscribers.lock() {
            Ok(subs) => subs.clone(),
            Err(_) => return,
        };
        for cb in callbacks {
            cb(event);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn publishes_events_to_subscribers() {
        let bus = EventBus::new();
        let count = Arc::new(AtomicUsize::new(0));
        let count_clone = count.clone();

        bus.subscribe(move |evt| {
            if matches!(evt, DomainEvent::ModuleToggled { .. }) {
                count_clone.fetch_add(1, Ordering::SeqCst);
            }
        });

        bus.publish(&DomainEvent::ModuleToggled {
            module_id: "clipboard".to_string(),
            enabled: true,
        });

        assert_eq!(count.load(Ordering::SeqCst), 1);
    }
}
