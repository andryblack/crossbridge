/*-
 * Copyright (c) 2004, David Xu <davidxu@freebsd.org>
 * Copyright (c) 2002, Jeffrey Roberson <jeff@freebsd.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice unmodified, this list of conditions, and the following
 *    disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/cdefs.h>
__FBSDID("$FreeBSD$");

#ifndef __AVM2__
#include "opt_compat.h"
#endif
#include <sys/param.h>
#include <sys/kernel.h>
#include <sys/limits.h>
#include <sys/lock.h>
#ifndef __AVM2__
#include <sys/malloc.h>
#endif
#include <sys/mutex.h>
#include <sys/priv.h>
#include <sys/proc.h>
#ifndef __AVM2__
#include <sys/sched.h>
#endif
#include <sys/smp.h>
#include <sys/sysctl.h>
#include <sys/sysent.h>
#include <sys/systm.h>
#include <sys/sysproto.h>
#include <sys/eventhandler.h>
#include <sys/umtx.h>

#ifndef __AVM2__
#include <vm/vm.h>
#include <vm/vm_param.h>
#include <vm/pmap.h>
#include <vm/vm_map.h>
#include <vm/vm_object.h>
#endif

#include <machine/cpu.h>

#ifdef COMPAT_FREEBSD32
#include <compat/freebsd32/freebsd32_proto.h>
#endif

#ifdef __AVM2__
#define _umtx_op k_umtx_op
// TODO move into some kind of fake kernel header?
extern void *kmalloc(size_t size, ...);
extern void kfree(void *ptr, ...);
#define malloc kmalloc
#define free kfree
#define msleep kmsleep
#define wakeup kwakeup
#define wakeup_one kwakeup_one
#define getnanouptime kgetnanouptime
#define tvtohz ktvtohz
#define thread_lock(X) /*thread_lock*/
#define thread_unlock(X) /*thread_unlock*/
#define copyin(A, B, C) (memcpy((A), (B), (C)), 0)
#define fuword(A) (*(volatile u_long *)(A))
#define fuword32(A) (*(volatile uint32_t *)(A))
#define suword(A, B) (((*(volatile u_long *)(A)) = (B)), 0)
#define suword32(A, B) (((*(volatile uint32_t *)(A)) = (B)), 0)
#define casuword __sync_val_compare_and_swap
#define casuword32 __sync_val_compare_and_swap
#define curthread ((void *)__curthread())

#define mtx_assert(...) /*mtx_assert*/
#define mtx_init kmtx_init
#define mtx_lock kmtx_lock
#define mtx_unlock kmtx_unlock
#define mtx_lock_spin kmtx_lock
#define mtx_unlock_spin kmtx_unlock
#endif

#define TYPE_SIMPLE_WAIT	0
#define TYPE_CV			1
#define TYPE_SIMPLE_LOCK	2
#define TYPE_NORMAL_UMUTEX	3
#define TYPE_PI_UMUTEX		4
#define TYPE_PP_UMUTEX		5
#define TYPE_RWLOCK		6

#define _UMUTEX_TRY		1
#define _UMUTEX_WAIT		2

/* Key to represent a unique userland synchronous object */
struct umtx_key {
	int	hash;
	int	type;
	int	shared;
	union {
#ifndef __AVM2__
		struct {
			vm_object_t	object;
			uintptr_t	offset;
		} shared;
		struct {
			struct vmspace	*vs;
			uintptr_t	addr;
		} private;
#endif
		struct {
			void		*a;
			uintptr_t	b;
		} both;
	} info;
};

#ifndef __AVM2__
/* Priority inheritance mutex info. */
struct umtx_pi {
	/* Owner thread */
	struct thread		*pi_owner;

	/* Reference count */
	int			pi_refcount;

 	/* List entry to link umtx holding by thread */
	TAILQ_ENTRY(umtx_pi)	pi_link;

	/* List entry in hash */
	TAILQ_ENTRY(umtx_pi)	pi_hashlink;

	/* List for waiters */
	TAILQ_HEAD(,umtx_q)	pi_blocked;

	/* Identify a userland lock object */
	struct umtx_key		pi_key;
};
#endif

/* A userland synchronous object user. */
struct umtx_q {
	/* Linked list for the hash. */
	TAILQ_ENTRY(umtx_q)	uq_link;

	/* Umtx key. */
	struct umtx_key		uq_key;

	/* Umtx flags. */
	int			uq_flags;
#define UQF_UMTXQ	0x0001

	/* The thread waits on. */
	struct thread		*uq_thread;

#ifndef __AVM2__
	/*
	 * Blocked on PI mutex. read can use chain lock
	 * or umtx_lock, write must have both chain lock and
	 * umtx_lock being hold.
	 */
	struct umtx_pi		*uq_pi_blocked;
#endif

	/* On blocked list */
	TAILQ_ENTRY(umtx_q)	uq_lockq;

#ifndef __AVM2__
	/* Thread contending with us */
	TAILQ_HEAD(,umtx_pi)	uq_pi_contested;
#endif

	/* Inherited priority from PP mutex */
	u_char			uq_inherited_pri;
};

TAILQ_HEAD(umtxq_head, umtx_q);

/* Userland lock object's wait-queue chain */
struct umtxq_chain {
	/* Lock for this chain. */
	struct mtx		uc_lock;

	/* List of sleep queues. */
	struct umtxq_head	uc_queue[2];
#define UMTX_SHARED_QUEUE	0
#define UMTX_EXCLUSIVE_QUEUE	1

	/* Busy flag */
	char			uc_busy;

	/* Chain lock waiters */
	int			uc_waiters;

#ifndef __AVM2__
	/* All PI in the list */
	TAILQ_HEAD(,umtx_pi)	uc_pi_list;
#endif
};

#define	UMTXQ_LOCKED_ASSERT(uc)		mtx_assert(&(uc)->uc_lock, MA_OWNED)
#define	UMTXQ_BUSY_ASSERT(uc)	KASSERT(&(uc)->uc_busy, ("umtx chain is not busy"))

/*
 * Don't propagate time-sharing priority, there is a security reason,
 * a user can simply introduce PI-mutex, let thread A lock the mutex,
 * and let another thread B block on the mutex, because B is
 * sleeping, its priority will be boosted, this causes A's priority to
 * be boosted via priority propagating too and will never be lowered even
 * if it is using 100%CPU, this is unfair to other processes.
 */

#define UPRI(td)	(((td)->td_user_pri >= PRI_MIN_TIMESHARE &&\
			  (td)->td_user_pri <= PRI_MAX_TIMESHARE) ?\
			 PRI_MAX_TIMESHARE : (td)->td_user_pri)

#define	GOLDEN_RATIO_PRIME	2654404609U
#define	UMTX_CHAINS		128
#define	UMTX_SHIFTS		(__WORD_BIT - 7)

#define THREAD_SHARE		0
#define PROCESS_SHARE		1
#define AUTO_SHARE		2

#define	GET_SHARE(flags)	\
    (((flags) & USYNC_PROCESS_SHARED) == 0 ? THREAD_SHARE : PROCESS_SHARE)

#define BUSY_SPINS		200

#ifndef __AVM2__
static uma_zone_t		umtx_pi_zone;
#endif
static struct umtxq_chain	umtxq_chains[2][UMTX_CHAINS];
#ifndef __AVM2__
static MALLOC_DEFINE(M_UMTX, "umtx", "UMTX queue memory");
#else
#define M_UMTX -1
#endif
#ifndef __AVM2__
static int			umtx_pi_allocated;
#endif

#ifndef __AVM2__
SYSCTL_NODE(_debug, OID_AUTO, umtx, CTLFLAG_RW, 0, "umtx debug");
SYSCTL_INT(_debug_umtx, OID_AUTO, umtx_pi_allocated, CTLFLAG_RD,
    &umtx_pi_allocated, 0, "Allocated umtx_pi");
#endif

static void umtxq_sysinit(void *);
static void umtxq_hash(struct umtx_key *key);
static struct umtxq_chain *umtxq_getchain(struct umtx_key *key);
static void umtxq_lock(struct umtx_key *key);
static void umtxq_unlock(struct umtx_key *key);
static void umtxq_busy(struct umtx_key *key);
static void umtxq_unbusy(struct umtx_key *key);
static void umtxq_insert_queue(struct umtx_q *uq, int q);
static void umtxq_remove_queue(struct umtx_q *uq, int q);
static int umtxq_sleep(struct umtx_q *uq, const char *wmesg, int timo);
static int umtxq_count(struct umtx_key *key);
static int umtx_key_match(const struct umtx_key *k1, const struct umtx_key *k2);
static int umtx_key_get(void *addr, int type, int share,
	struct umtx_key *key);
static void umtx_key_release(struct umtx_key *key);
#ifndef __AVM2__
static struct umtx_pi *umtx_pi_alloc(int);
static void umtx_pi_free(struct umtx_pi *pi);
static void umtx_pi_adjust_locked(struct thread *td, u_char oldpri);
static int do_unlock_pp(struct thread *td, struct umutex *m, uint32_t flags);
#endif
static void umtx_thread_cleanup(struct thread *td);
static void umtx_exec_hook(void *arg __unused, struct proc *p __unused,
	struct image_params *imgp __unused);

#ifndef __AVM2__
SYSINIT(umtx, SI_SUB_EVENTHANDLER+1, SI_ORDER_MIDDLE, umtxq_sysinit, NULL);
#endif

#define umtxq_signal(key, nwake)	umtxq_signal_queue((key), (nwake), UMTX_SHARED_QUEUE)
#define umtxq_insert(uq)	umtxq_insert_queue((uq), UMTX_SHARED_QUEUE)
#define umtxq_remove(uq)	umtxq_remove_queue((uq), UMTX_SHARED_QUEUE)

static struct mtx umtx_lock;

static void
umtxq_sysinit(void *arg __unused)
{
	int i, j;

#ifndef __AVM2__
	umtx_pi_zone = uma_zcreate("umtx pi", sizeof(struct umtx_pi),
		NULL, NULL, NULL, NULL, UMA_ALIGN_PTR, 0);
#endif
	for (i = 0; i < 2; ++i) {
		for (j = 0; j < UMTX_CHAINS; ++j) {
			mtx_init(&umtxq_chains[i][j].uc_lock, "umtxql", NULL,
				 MTX_DEF | MTX_DUPOK);
			TAILQ_INIT(&umtxq_chains[i][j].uc_queue[0]);
			TAILQ_INIT(&umtxq_chains[i][j].uc_queue[1]);
#ifndef __AVM2__
			TAILQ_INIT(&umtxq_chains[i][j].uc_pi_list);
#endif
			umtxq_chains[i][j].uc_busy = 0;
			umtxq_chains[i][j].uc_waiters = 0;
		}
	}
	mtx_init(&umtx_lock, "umtx lock", NULL, MTX_SPIN);
#ifndef __AVM2__
	EVENTHANDLER_REGISTER(process_exec, umtx_exec_hook, NULL,
	    EVENTHANDLER_PRI_ANY);
#endif
}

#ifdef __AVM2__
static void
_umtxq_sysinit() __attribute__((constructor));
static void
_umtxq_sysinit()
{
  umtxq_sysinit(NULL);
}
#endif

struct umtx_q *
umtxq_alloc(void)
{
	struct umtx_q *uq;

	uq = malloc(sizeof(struct umtx_q), M_UMTX, M_WAITOK | M_ZERO);
#ifndef __AVM2__
	TAILQ_INIT(&uq->uq_pi_contested);
#endif
	uq->uq_inherited_pri = PRI_MAX;
	return (uq);
}

void
umtxq_free(struct umtx_q *uq)
{
	free(uq, M_UMTX);
}

static inline void
umtxq_hash(struct umtx_key *key)
{
	unsigned n = (uintptr_t)key->info.both.a + key->info.both.b;
	key->hash = ((n * GOLDEN_RATIO_PRIME) >> UMTX_SHIFTS) % UMTX_CHAINS;
}

static inline int
umtx_key_match(const struct umtx_key *k1, const struct umtx_key *k2)
{
	return (k1->type == k2->type &&
		k1->info.both.a == k2->info.both.a &&
	        k1->info.both.b == k2->info.both.b);
}

static inline struct umtxq_chain *
umtxq_getchain(struct umtx_key *key)
{
	if (key->type <= TYPE_CV)
		return (&umtxq_chains[1][key->hash]);
	return (&umtxq_chains[0][key->hash]);
}

/*
 * Lock a chain.
 */
static inline void
umtxq_lock(struct umtx_key *key)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(key);
	mtx_lock(&uc->uc_lock);
}

/*
 * Unlock a chain.
 */
static inline void
umtxq_unlock(struct umtx_key *key)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(key);
	mtx_unlock(&uc->uc_lock);
}

/*
 * Set chain to busy state when following operation
 * may be blocked (kernel mutex can not be used).
 */
static inline void
umtxq_busy(struct umtx_key *key)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(key);
	mtx_assert(&uc->uc_lock, MA_OWNED);
	if (uc->uc_busy) {
#ifdef SMP
		if (smp_cpus > 1) {
			int count = BUSY_SPINS;
			if (count > 0) {
				umtxq_unlock(key);
				while (uc->uc_busy && --count > 0)
					cpu_spinwait();
				umtxq_lock(key);
			}
		}
#endif
		while (uc->uc_busy) {
			uc->uc_waiters++;
			msleep(uc, &uc->uc_lock, 0, "umtxqb", 0);
			uc->uc_waiters--;
		}
	}
	uc->uc_busy = 1;
}

/*
 * Unbusy a chain.
 */
static inline void
umtxq_unbusy(struct umtx_key *key)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(key);
	mtx_assert(&uc->uc_lock, MA_OWNED);
	KASSERT(uc->uc_busy != 0, ("not busy"));
	uc->uc_busy = 0;
	if (uc->uc_waiters)
		wakeup_one(uc);
}

static inline void
umtxq_insert_queue(struct umtx_q *uq, int q)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&uq->uq_key);
	UMTXQ_LOCKED_ASSERT(uc);
	TAILQ_INSERT_TAIL(&uc->uc_queue[q], uq, uq_link);
	uq->uq_flags |= UQF_UMTXQ;
}

static inline void
umtxq_remove_queue(struct umtx_q *uq, int q)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&uq->uq_key);
	UMTXQ_LOCKED_ASSERT(uc);
	if (uq->uq_flags & UQF_UMTXQ) {
		TAILQ_REMOVE(&uc->uc_queue[q], uq, uq_link);
		uq->uq_flags &= ~UQF_UMTXQ;
	}
}

/*
 * Check if there are multiple waiters
 */
static int
umtxq_count(struct umtx_key *key)
{
	struct umtxq_chain *uc;
	struct umtx_q *uq;
	int count = 0;

	uc = umtxq_getchain(key);
	UMTXQ_LOCKED_ASSERT(uc);
	TAILQ_FOREACH(uq, &uc->uc_queue[UMTX_SHARED_QUEUE], uq_link) {
		if (umtx_key_match(&uq->uq_key, key)) {
			if (++count > 1)
				break;
		}
	}
	return (count);
}

/*
 * Check if there are multiple PI waiters and returns first
 * waiter.
 */
static int
umtxq_count_pi(struct umtx_key *key, struct umtx_q **first)
{
	struct umtxq_chain *uc;
	struct umtx_q *uq;
	int count = 0;

	*first = NULL;
	uc = umtxq_getchain(key);
	UMTXQ_LOCKED_ASSERT(uc);
	TAILQ_FOREACH(uq, &uc->uc_queue[UMTX_SHARED_QUEUE], uq_link) {
		if (umtx_key_match(&uq->uq_key, key)) {
			if (++count > 1)
				break;
			*first = uq;
		}
	}
	return (count);
}

/*
 * Wake up threads waiting on an userland object.
 */

static int
umtxq_signal_queue(struct umtx_key *key, int n_wake, int q)
{
	struct umtxq_chain *uc;
	struct umtx_q *uq, *next;
	int ret;

	ret = 0;
	uc = umtxq_getchain(key);
	UMTXQ_LOCKED_ASSERT(uc);
	TAILQ_FOREACH_SAFE(uq, &uc->uc_queue[q], uq_link, next) {
		if (umtx_key_match(&uq->uq_key, key)) {
			umtxq_remove_queue(uq, q);
			wakeup(uq);
			if (++ret >= n_wake)
				break;
		}
	}
	return (ret);
}


/*
 * Wake up specified thread.
 */
static inline void
umtxq_signal_thread(struct umtx_q *uq)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&uq->uq_key);
	UMTXQ_LOCKED_ASSERT(uc);
	umtxq_remove(uq);
	wakeup(uq);
}

/*
 * Put thread into sleep state, before sleeping, check if
 * thread was removed from umtx queue.
 */
static inline int
umtxq_sleep(struct umtx_q *uq, const char *wmesg, int timo)
{
	struct umtxq_chain *uc;
	int error;

	uc = umtxq_getchain(&uq->uq_key);
	UMTXQ_LOCKED_ASSERT(uc);
	if (!(uq->uq_flags & UQF_UMTXQ))
		return (0);
	error = msleep(uq, &uc->uc_lock, PCATCH, wmesg, timo);
	if (error == EWOULDBLOCK)
		error = ETIMEDOUT;
	return (error);
}

/*
 * Convert userspace address into unique logical address.
 */
static int
umtx_key_get(void *addr, int type, int share, struct umtx_key *key)
{
#ifdef __AVM2__
        key->type = type;
        key->shared = 0;
	key->info.both.a = addr;
	key->info.both.b = 0;
#else
	struct thread *td = curthread;
	vm_map_t map;
	vm_map_entry_t entry;
	vm_pindex_t pindex;
	vm_prot_t prot;
	boolean_t wired;

	key->type = type;
	if (share == THREAD_SHARE) {
		key->shared = 0;
		key->info.private.vs = td->td_proc->p_vmspace;
		key->info.private.addr = (uintptr_t)addr;
	} else {
		MPASS(share == PROCESS_SHARE || share == AUTO_SHARE);
		map = &td->td_proc->p_vmspace->vm_map;
		if (vm_map_lookup(&map, (vm_offset_t)addr, VM_PROT_WRITE,
		    &entry, &key->info.shared.object, &pindex, &prot,
		    &wired) != KERN_SUCCESS) {
			return EFAULT;
		}

		if ((share == PROCESS_SHARE) ||
		    (share == AUTO_SHARE &&
		     VM_INHERIT_SHARE == entry->inheritance)) {
			key->shared = 1;
			key->info.shared.offset = entry->offset + entry->start -
				(vm_offset_t)addr;
			vm_object_reference(key->info.shared.object);
		} else {
			key->shared = 0;
			key->info.private.vs = td->td_proc->p_vmspace;
			key->info.private.addr = (uintptr_t)addr;
		}
		vm_map_lookup_done(map, entry);
	}
#endif
	umtxq_hash(key);
	return (0);
}

/*
 * Release key.
 */
static inline void
umtx_key_release(struct umtx_key *key)
{
#ifndef __AVM2__
	if (key->shared)
		vm_object_deallocate(key->info.shared.object);
#endif
}

/*
 * Lock a umtx object.
 */
static int
_do_lock_umtx(struct thread *td, struct umtx *umtx, u_long id, int timo)
{
	struct umtx_q *uq;
	u_long owner;
	u_long old;
	int error = 0;

	uq = td->td_umtxq;

	/*
	 * Care must be exercised when dealing with umtx structure. It
	 * can fault on any access.
	 */
	for (;;) {
		/*
		 * Try the uncontested case.  This should be done in userland.
		 */
		owner = casuword(&umtx->u_owner, UMTX_UNOWNED, id);

		/* The acquire succeeded. */
		if (owner == UMTX_UNOWNED)
			return (0);

		/* The address was invalid. */
		if (owner == -1)
			return (EFAULT);

		/* If no one owns it but it is contested try to acquire it. */
		if (owner == UMTX_CONTESTED) {
			owner = casuword(&umtx->u_owner,
			    UMTX_CONTESTED, id | UMTX_CONTESTED);

			if (owner == UMTX_CONTESTED)
				return (0);

			/* The address was invalid. */
			if (owner == -1)
				return (EFAULT);

			/* If this failed the lock has changed, restart. */
			continue;
		}

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			return (error);

		if ((error = umtx_key_get(umtx, TYPE_SIMPLE_LOCK,
			AUTO_SHARE, &uq->uq_key)) != 0)
			return (error);

		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_insert(uq);
		umtxq_unbusy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		/*
		 * Set the contested bit so that a release in user space
		 * knows to use the system call for unlock.  If this fails
		 * either some one else has acquired the lock or it has been
		 * released.
		 */
		old = casuword(&umtx->u_owner, owner, owner | UMTX_CONTESTED);

		/* The address was invalid. */
		if (old == -1) {
			umtxq_lock(&uq->uq_key);
			umtxq_remove(uq);
			umtxq_unlock(&uq->uq_key);
			umtx_key_release(&uq->uq_key);
			return (EFAULT);
		}

		/*
		 * We set the contested bit, sleep. Otherwise the lock changed
		 * and we need to retry or we lost a race to the thread
		 * unlocking the umtx.
		 */
		umtxq_lock(&uq->uq_key);
		if (old == owner)
			error = umtxq_sleep(uq, "umtx", timo);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
		umtx_key_release(&uq->uq_key);
	}

	return (0);
}

/*
 * Lock a umtx object.
 */
static int
do_lock_umtx(struct thread *td, struct umtx *umtx, u_long id,
	struct timespec *timeout)
{
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	int error;

	if (timeout == NULL) {
		error = _do_lock_umtx(td, umtx, id, 0);
		/* Mutex locking is restarted if it is interrupted. */
		if (error == EINTR)
			error = ERESTART;
	} else {
		getnanouptime(&ts);
		timespecadd(&ts, timeout);
		TIMESPEC_TO_TIMEVAL(&tv, timeout);
		for (;;) {
			error = _do_lock_umtx(td, umtx, id, tvtohz(&tv));
			if (error != ETIMEDOUT)
				break;
			getnanouptime(&ts2);
			if (timespeccmp(&ts2, &ts, >=)) {
				error = ETIMEDOUT;
				break;
			}
			ts3 = ts;
			timespecsub(&ts3, &ts2);
			TIMESPEC_TO_TIMEVAL(&tv, &ts3);
		}
		/* Timed-locking is not restarted. */
		if (error == ERESTART)
			error = EINTR;
	}
	return (error);
}

/*
 * Unlock a umtx object.
 */
static int
do_unlock_umtx(struct thread *td, struct umtx *umtx, u_long id)
{
	struct umtx_key key;
	u_long owner;
	u_long old;
	int error;
	int count;

	/*
	 * Make sure we own this mtx.
	 */
	owner = fuword(__DEVOLATILE(u_long *, &umtx->u_owner));
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMTX_CONTESTED) != id)
		return (EPERM);

	/* This should be done in userland */
	if ((owner & UMTX_CONTESTED) == 0) {
		old = casuword(&umtx->u_owner, owner, UMTX_UNOWNED);
		if (old == -1)
			return (EFAULT);
		if (old == owner)
			return (0);
		owner = old;
	}

	/* We should only ever be in here for contested locks */
	if ((error = umtx_key_get(umtx, TYPE_SIMPLE_LOCK, AUTO_SHARE,
		&key)) != 0)
		return (error);

	umtxq_lock(&key);
	umtxq_busy(&key);
	count = umtxq_count(&key);
	umtxq_unlock(&key);

	/*
	 * When unlocking the umtx, it must be marked as unowned if
	 * there is zero or one thread only waiting for it.
	 * Otherwise, it must be marked as contested.
	 */
	old = casuword(&umtx->u_owner, owner,
		count <= 1 ? UMTX_UNOWNED : UMTX_CONTESTED);
	umtxq_lock(&key);
	umtxq_signal(&key,1);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	if (old == -1)
		return (EFAULT);
	if (old != owner)
		return (EINVAL);
	return (0);
}

#ifdef COMPAT_FREEBSD32

/*
 * Lock a umtx object.
 */
static int
_do_lock_umtx32(struct thread *td, uint32_t *m, uint32_t id, int timo)
{
	struct umtx_q *uq;
	uint32_t owner;
	uint32_t old;
	int error = 0;

	uq = td->td_umtxq;

	/*
	 * Care must be exercised when dealing with umtx structure. It
	 * can fault on any access.
	 */
	for (;;) {
		/*
		 * Try the uncontested case.  This should be done in userland.
		 */
		owner = casuword32(m, UMUTEX_UNOWNED, id);

		/* The acquire succeeded. */
		if (owner == UMUTEX_UNOWNED)
			return (0);

		/* The address was invalid. */
		if (owner == -1)
			return (EFAULT);

		/* If no one owns it but it is contested try to acquire it. */
		if (owner == UMUTEX_CONTESTED) {
			owner = casuword32(m,
			    UMUTEX_CONTESTED, id | UMUTEX_CONTESTED);
			if (owner == UMUTEX_CONTESTED)
				return (0);

			/* The address was invalid. */
			if (owner == -1)
				return (EFAULT);

			/* If this failed the lock has changed, restart. */
			continue;
		}

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			return (error);

		if ((error = umtx_key_get(m, TYPE_SIMPLE_LOCK,
			AUTO_SHARE, &uq->uq_key)) != 0)
			return (error);

		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_insert(uq);
		umtxq_unbusy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		/*
		 * Set the contested bit so that a release in user space
		 * knows to use the system call for unlock.  If this fails
		 * either some one else has acquired the lock or it has been
		 * released.
		 */
		old = casuword32(m, owner, owner | UMUTEX_CONTESTED);

		/* The address was invalid. */
		if (old == -1) {
			umtxq_lock(&uq->uq_key);
			umtxq_remove(uq);
			umtxq_unlock(&uq->uq_key);
			umtx_key_release(&uq->uq_key);
			return (EFAULT);
		}

		/*
		 * We set the contested bit, sleep. Otherwise the lock changed
		 * and we need to retry or we lost a race to the thread
		 * unlocking the umtx.
		 */
		umtxq_lock(&uq->uq_key);
		if (old == owner)
			error = umtxq_sleep(uq, "umtx", timo);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
		umtx_key_release(&uq->uq_key);
	}

	return (0);
}

/*
 * Lock a umtx object.
 */
static int
do_lock_umtx32(struct thread *td, void *m, uint32_t id,
	struct timespec *timeout)
{
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	int error;

	if (timeout == NULL) {
		error = _do_lock_umtx32(td, m, id, 0);
		/* Mutex locking is restarted if it is interrupted. */
		if (error == EINTR)
			error = ERESTART;
	} else {
		getnanouptime(&ts);
		timespecadd(&ts, timeout);
		TIMESPEC_TO_TIMEVAL(&tv, timeout);
		for (;;) {
			error = _do_lock_umtx32(td, m, id, tvtohz(&tv));
			if (error != ETIMEDOUT)
				break;
			getnanouptime(&ts2);
			if (timespeccmp(&ts2, &ts, >=)) {
				error = ETIMEDOUT;
				break;
			}
			ts3 = ts;
			timespecsub(&ts3, &ts2);
			TIMESPEC_TO_TIMEVAL(&tv, &ts3);
		}
		/* Timed-locking is not restarted. */
		if (error == ERESTART)
			error = EINTR;
	}
	return (error);
}

/*
 * Unlock a umtx object.
 */
static int
do_unlock_umtx32(struct thread *td, uint32_t *m, uint32_t id)
{
	struct umtx_key key;
	uint32_t owner;
	uint32_t old;
	int error;
	int count;

	/*
	 * Make sure we own this mtx.
	 */
	owner = fuword32(m);
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMUTEX_CONTESTED) != id)
		return (EPERM);

	/* This should be done in userland */
	if ((owner & UMUTEX_CONTESTED) == 0) {
		old = casuword32(m, owner, UMUTEX_UNOWNED);
		if (old == -1)
			return (EFAULT);
		if (old == owner)
			return (0);
		owner = old;
	}

	/* We should only ever be in here for contested locks */
	if ((error = umtx_key_get(m, TYPE_SIMPLE_LOCK, AUTO_SHARE,
		&key)) != 0)
		return (error);

	umtxq_lock(&key);
	umtxq_busy(&key);
	count = umtxq_count(&key);
	umtxq_unlock(&key);

	/*
	 * When unlocking the umtx, it must be marked as unowned if
	 * there is zero or one thread only waiting for it.
	 * Otherwise, it must be marked as contested.
	 */
	old = casuword32(m, owner,
		count <= 1 ? UMUTEX_UNOWNED : UMUTEX_CONTESTED);
	umtxq_lock(&key);
	umtxq_signal(&key,1);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	if (old == -1)
		return (EFAULT);
	if (old != owner)
		return (EINVAL);
	return (0);
}
#endif

/*
 * Fetch and compare value, sleep on the address if value is not changed.
 */
static int
do_wait(struct thread *td, void *addr, u_long id,
	struct timespec *timeout, int compat32, int is_private)
{
	struct umtx_q *uq;
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	u_long tmp;
	int error = 0;

	uq = td->td_umtxq;
	if ((error = umtx_key_get(addr, TYPE_SIMPLE_WAIT,
		is_private ? THREAD_SHARE : AUTO_SHARE, &uq->uq_key)) != 0)
		return (error);

	umtxq_lock(&uq->uq_key);
	umtxq_insert(uq);
	umtxq_unlock(&uq->uq_key);
	if (compat32 == 0)
		tmp = fuword(addr);
        else
		tmp = (unsigned int)fuword32(addr);
	if (tmp != id) {
		umtxq_lock(&uq->uq_key);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
	} else if (timeout == NULL) {
		umtxq_lock(&uq->uq_key);
		error = umtxq_sleep(uq, "uwait", 0);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
	} else {
		getnanouptime(&ts);
		timespecadd(&ts, timeout);
		TIMESPEC_TO_TIMEVAL(&tv, timeout);
		umtxq_lock(&uq->uq_key);
		for (;;) {
			error = umtxq_sleep(uq, "uwait", tvtohz(&tv));
			if (!(uq->uq_flags & UQF_UMTXQ))
				break;
			if (error != ETIMEDOUT)
				break;
			umtxq_unlock(&uq->uq_key);
			getnanouptime(&ts2);
			if (timespeccmp(&ts2, &ts, >=)) {
				error = ETIMEDOUT;
				umtxq_lock(&uq->uq_key);
				break;
			}
			ts3 = ts;
			timespecsub(&ts3, &ts2);
			TIMESPEC_TO_TIMEVAL(&tv, &ts3);
			umtxq_lock(&uq->uq_key);
		}
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
	}
	umtx_key_release(&uq->uq_key);
	if (error == ERESTART)
		error = EINTR;
	return (error);
}

/*
 * Wake up threads sleeping on the specified address.
 */
int
kern_umtx_wake(struct thread *td, void *uaddr, int n_wake, int is_private)
{
	struct umtx_key key;
	int ret;
	
	if ((ret = umtx_key_get(uaddr, TYPE_SIMPLE_WAIT,
		is_private ? THREAD_SHARE : AUTO_SHARE, &key)) != 0)
		return (ret);
	umtxq_lock(&key);
	ret = umtxq_signal(&key, n_wake);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	return (0);
}

/*
 * Lock PTHREAD_PRIO_NONE protocol POSIX mutex.
 */
static int
_do_lock_normal(struct thread *td, struct umutex *m, uint32_t flags, int timo,
	int mode)
{
	struct umtx_q *uq;
	uint32_t owner, old, id;
	int error = 0;

	id = td->td_tid;
	uq = td->td_umtxq;

	/*
	 * Care must be exercised when dealing with umtx structure. It
	 * can fault on any access.
	 */
	for (;;) {
		owner = fuword32(__DEVOLATILE(void *, &m->m_owner));
		if (mode == _UMUTEX_WAIT) {
			if (owner == UMUTEX_UNOWNED || owner == UMUTEX_CONTESTED)
				return (0);
		} else {
			/*
			 * Try the uncontested case.  This should be done in userland.
			 */
			owner = casuword32(&m->m_owner, UMUTEX_UNOWNED, id);

			/* The acquire succeeded. */
			if (owner == UMUTEX_UNOWNED)
				return (0);

			/* The address was invalid. */
			if (owner == -1)
				return (EFAULT);

			/* If no one owns it but it is contested try to acquire it. */
			if (owner == UMUTEX_CONTESTED) {
				owner = casuword32(&m->m_owner,
				    UMUTEX_CONTESTED, id | UMUTEX_CONTESTED);

				if (owner == UMUTEX_CONTESTED)
					return (0);

				/* The address was invalid. */
				if (owner == -1)
					return (EFAULT);

				/* If this failed the lock has changed, restart. */
				continue;
			}
		}

		if ((flags & UMUTEX_ERROR_CHECK) != 0 &&
		    (owner & ~UMUTEX_CONTESTED) == id)
			return (EDEADLK);

		if (mode == _UMUTEX_TRY)
			return (EBUSY);

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			return (error);

		if ((error = umtx_key_get(m, TYPE_NORMAL_UMUTEX,
		    GET_SHARE(flags), &uq->uq_key)) != 0)
			return (error);

		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_insert(uq);
		umtxq_unlock(&uq->uq_key);

		/*
		 * Set the contested bit so that a release in user space
		 * knows to use the system call for unlock.  If this fails
		 * either some one else has acquired the lock or it has been
		 * released.
		 */
		old = casuword32(&m->m_owner, owner, owner | UMUTEX_CONTESTED);

		/* The address was invalid. */
		if (old == -1) {
			umtxq_lock(&uq->uq_key);
			umtxq_remove(uq);
			umtxq_unbusy(&uq->uq_key);
			umtxq_unlock(&uq->uq_key);
			umtx_key_release(&uq->uq_key);
			return (EFAULT);
		}

		/*
		 * We set the contested bit, sleep. Otherwise the lock changed
		 * and we need to retry or we lost a race to the thread
		 * unlocking the umtx.
		 */
		umtxq_lock(&uq->uq_key);
		umtxq_unbusy(&uq->uq_key);
		if (old == owner)
			error = umtxq_sleep(uq, "umtxn", timo);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
		umtx_key_release(&uq->uq_key);
	}

	return (0);
}

/*
 * Lock PTHREAD_PRIO_NONE protocol POSIX mutex.
 */
/*
 * Unlock PTHREAD_PRIO_NONE protocol POSIX mutex.
 */
static int
do_unlock_normal(struct thread *td, struct umutex *m, uint32_t flags)
{
	struct umtx_key key;
	uint32_t owner, old, id;
	int error;
	int count;

	id = td->td_tid;
	/*
	 * Make sure we own this mtx.
	 */
	owner = fuword32(__DEVOLATILE(uint32_t *, &m->m_owner));
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMUTEX_CONTESTED) != id)
		return (EPERM);

	if ((owner & UMUTEX_CONTESTED) == 0) {
		old = casuword32(&m->m_owner, owner, UMUTEX_UNOWNED);
		if (old == -1)
			return (EFAULT);
		if (old == owner)
			return (0);
		owner = old;
	}

	/* We should only ever be in here for contested locks */
	if ((error = umtx_key_get(m, TYPE_NORMAL_UMUTEX, GET_SHARE(flags),
	    &key)) != 0)
		return (error);

	umtxq_lock(&key);
	umtxq_busy(&key);
	count = umtxq_count(&key);
	umtxq_unlock(&key);

	/*
	 * When unlocking the umtx, it must be marked as unowned if
	 * there is zero or one thread only waiting for it.
	 * Otherwise, it must be marked as contested.
	 */
	old = casuword32(&m->m_owner, owner,
		count <= 1 ? UMUTEX_UNOWNED : UMUTEX_CONTESTED);
	umtxq_lock(&key);
	umtxq_signal(&key,1);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	if (old == -1)
		return (EFAULT);
	if (old != owner)
		return (EINVAL);
	return (0);
}

/*
 * Check if the mutex is available and wake up a waiter,
 * only for simple mutex.
 */
static int
do_wake_umutex(struct thread *td, struct umutex *m)
{
	struct umtx_key key;
	uint32_t owner;
	uint32_t flags;
	int error;
	int count;

	owner = fuword32(__DEVOLATILE(uint32_t *, &m->m_owner));
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMUTEX_CONTESTED) != 0)
		return (0);

	flags = fuword32(&m->m_flags);

	/* We should only ever be in here for contested locks */
	if ((error = umtx_key_get(m, TYPE_NORMAL_UMUTEX, GET_SHARE(flags),
	    &key)) != 0)
		return (error);

	umtxq_lock(&key);
	umtxq_busy(&key);
	count = umtxq_count(&key);
	umtxq_unlock(&key);

	if (count <= 1)
		owner = casuword32(&m->m_owner, UMUTEX_CONTESTED, UMUTEX_UNOWNED);

	umtxq_lock(&key);
	if (count != 0 && (owner & ~UMUTEX_CONTESTED) == 0)
		umtxq_signal(&key, 1);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	return (0);
}

#ifndef __AVM2__
static inline struct umtx_pi *
umtx_pi_alloc(int flags)
{
	struct umtx_pi *pi;

	pi = uma_zalloc(umtx_pi_zone, M_ZERO | flags);
	TAILQ_INIT(&pi->pi_blocked);
	atomic_add_int(&umtx_pi_allocated, 1);
	return (pi);
}

static inline void
umtx_pi_free(struct umtx_pi *pi)
{
	uma_zfree(umtx_pi_zone, pi);
	atomic_add_int(&umtx_pi_allocated, -1);
}

/*
 * Adjust the thread's position on a pi_state after its priority has been
 * changed.
 */
static int
umtx_pi_adjust_thread(struct umtx_pi *pi, struct thread *td)
{
	struct umtx_q *uq, *uq1, *uq2;
	struct thread *td1;

	mtx_assert(&umtx_lock, MA_OWNED);
	if (pi == NULL)
		return (0);

	uq = td->td_umtxq;

	/*
	 * Check if the thread needs to be moved on the blocked chain.
	 * It needs to be moved if either its priority is lower than
	 * the previous thread or higher than the next thread.
	 */
	uq1 = TAILQ_PREV(uq, umtxq_head, uq_lockq);
	uq2 = TAILQ_NEXT(uq, uq_lockq);
	if ((uq1 != NULL && UPRI(td) < UPRI(uq1->uq_thread)) ||
	    (uq2 != NULL && UPRI(td) > UPRI(uq2->uq_thread))) {
		/*
		 * Remove thread from blocked chain and determine where
		 * it should be moved to.
		 */
		TAILQ_REMOVE(&pi->pi_blocked, uq, uq_lockq);
		TAILQ_FOREACH(uq1, &pi->pi_blocked, uq_lockq) {
			td1 = uq1->uq_thread;
			MPASS(td1->td_proc->p_magic == P_MAGIC);
			if (UPRI(td1) > UPRI(td))
				break;
		}

		if (uq1 == NULL)
			TAILQ_INSERT_TAIL(&pi->pi_blocked, uq, uq_lockq);
		else
			TAILQ_INSERT_BEFORE(uq1, uq, uq_lockq);
	}
	return (1);
}

/*
 * Propagate priority when a thread is blocked on POSIX
 * PI mutex.
 */ 
static void
umtx_propagate_priority(struct thread *td)
{
	struct umtx_q *uq;
	struct umtx_pi *pi;
	int pri;

	mtx_assert(&umtx_lock, MA_OWNED);
	pri = UPRI(td);
	uq = td->td_umtxq;
	pi = uq->uq_pi_blocked;
	if (pi == NULL)
		return;

	for (;;) {
		td = pi->pi_owner;
		if (td == NULL)
			return;

		MPASS(td->td_proc != NULL);
		MPASS(td->td_proc->p_magic == P_MAGIC);

		if (UPRI(td) <= pri)
			return;

		thread_lock(td);
		sched_lend_user_prio(td, pri);
		thread_unlock(td);

		/*
		 * Pick up the lock that td is blocked on.
		 */
		uq = td->td_umtxq;
		pi = uq->uq_pi_blocked;
		/* Resort td on the list if needed. */
		if (!umtx_pi_adjust_thread(pi, td))
			break;
	}
}

/*
 * Unpropagate priority for a PI mutex when a thread blocked on
 * it is interrupted by signal or resumed by others.
 */
static void
umtx_unpropagate_priority(struct umtx_pi *pi)
{
	struct umtx_q *uq, *uq_owner;
	struct umtx_pi *pi2;
	int pri, oldpri;

	mtx_assert(&umtx_lock, MA_OWNED);

	while (pi != NULL && pi->pi_owner != NULL) {
		pri = PRI_MAX;
		uq_owner = pi->pi_owner->td_umtxq;

		TAILQ_FOREACH(pi2, &uq_owner->uq_pi_contested, pi_link) {
			uq = TAILQ_FIRST(&pi2->pi_blocked);
			if (uq != NULL) {
				if (pri > UPRI(uq->uq_thread))
					pri = UPRI(uq->uq_thread);
			}
		}

		if (pri > uq_owner->uq_inherited_pri)
			pri = uq_owner->uq_inherited_pri;
		thread_lock(pi->pi_owner);
		oldpri = pi->pi_owner->td_user_pri;
		sched_unlend_user_prio(pi->pi_owner, pri);
		thread_unlock(pi->pi_owner);
		if (uq_owner->uq_pi_blocked != NULL)
			umtx_pi_adjust_locked(pi->pi_owner, oldpri);
		pi = uq_owner->uq_pi_blocked;
	}
}

/*
 * Insert a PI mutex into owned list.
 */
static void
umtx_pi_setowner(struct umtx_pi *pi, struct thread *owner)
{
	struct umtx_q *uq_owner;

	uq_owner = owner->td_umtxq;
	mtx_assert(&umtx_lock, MA_OWNED);
	if (pi->pi_owner != NULL)
		panic("pi_ower != NULL");
	pi->pi_owner = owner;
	TAILQ_INSERT_TAIL(&uq_owner->uq_pi_contested, pi, pi_link);
}

/*
 * Claim ownership of a PI mutex.
 */
static int
umtx_pi_claim(struct umtx_pi *pi, struct thread *owner)
{
	struct umtx_q *uq, *uq_owner;

	uq_owner = owner->td_umtxq;
	mtx_lock_spin(&umtx_lock);
	if (pi->pi_owner == owner) {
		mtx_unlock_spin(&umtx_lock);
		return (0);
	}

	if (pi->pi_owner != NULL) {
		/*
		 * userland may have already messed the mutex, sigh.
		 */
		mtx_unlock_spin(&umtx_lock);
		return (EPERM);
	}
	umtx_pi_setowner(pi, owner);
	uq = TAILQ_FIRST(&pi->pi_blocked);
	if (uq != NULL) {
		int pri;

		pri = UPRI(uq->uq_thread);
		thread_lock(owner);
		if (pri < UPRI(owner))
			sched_lend_user_prio(owner, pri);
		thread_unlock(owner);
	}
	mtx_unlock_spin(&umtx_lock);
	return (0);
}

static void
umtx_pi_adjust_locked(struct thread *td, u_char oldpri)
{
	struct umtx_q *uq;
	struct umtx_pi *pi;

	uq = td->td_umtxq;
	/*
	 * Pick up the lock that td is blocked on.
	 */
	pi = uq->uq_pi_blocked;
	MPASS(pi != NULL);

	/* Resort the turnstile on the list. */
	if (!umtx_pi_adjust_thread(pi, td))
		return;

	/*
	 * If our priority was lowered and we are at the head of the
	 * turnstile, then propagate our new priority up the chain.
	 */
	if (uq == TAILQ_FIRST(&pi->pi_blocked) && UPRI(td) < oldpri)
		umtx_propagate_priority(td);
}

/*
 * Adjust a thread's order position in its blocked PI mutex,
 * this may result new priority propagating process.
 */
void
umtx_pi_adjust(struct thread *td, u_char oldpri)
{
	struct umtx_q *uq;
	struct umtx_pi *pi;

	uq = td->td_umtxq;
	mtx_lock_spin(&umtx_lock);
	/*
	 * Pick up the lock that td is blocked on.
	 */
	pi = uq->uq_pi_blocked;
	if (pi != NULL)
		umtx_pi_adjust_locked(td, oldpri);
	mtx_unlock_spin(&umtx_lock);
}

/*
 * Sleep on a PI mutex.
 */
static int
umtxq_sleep_pi(struct umtx_q *uq, struct umtx_pi *pi,
	uint32_t owner, const char *wmesg, int timo)
{
	struct umtxq_chain *uc;
	struct thread *td, *td1;
	struct umtx_q *uq1;
	int pri;
	int error = 0;

	td = uq->uq_thread;
	KASSERT(td == curthread, ("inconsistent uq_thread"));
	uc = umtxq_getchain(&uq->uq_key);
	UMTXQ_LOCKED_ASSERT(uc);
	UMTXQ_BUSY_ASSERT(uc);
	umtxq_insert(uq);
	mtx_lock_spin(&umtx_lock);
	if (pi->pi_owner == NULL) {
		/* XXX
		 * Current, We only support process private PI-mutex,
		 * non-contended PI-mutexes are locked in userland.
		 * Process shared PI-mutex should always be initialized
		 * by kernel and be registered in kernel, locking should
		 * always be done by kernel to avoid security problems.
		 * For process private PI-mutex, we can find owner
		 * thread and boost its priority safely.
		 */
		mtx_unlock_spin(&umtx_lock);
		PROC_LOCK(curproc);
		td1 = thread_find(curproc, owner);
		mtx_lock_spin(&umtx_lock);
		if (td1 != NULL && pi->pi_owner == NULL) {
			uq1 = td1->td_umtxq;
			umtx_pi_setowner(pi, td1);
		}
		PROC_UNLOCK(curproc);
	}

	TAILQ_FOREACH(uq1, &pi->pi_blocked, uq_lockq) {
		pri = UPRI(uq1->uq_thread);
		if (pri > UPRI(td))
			break;
	}

	if (uq1 != NULL)
		TAILQ_INSERT_BEFORE(uq1, uq, uq_lockq);
	else
		TAILQ_INSERT_TAIL(&pi->pi_blocked, uq, uq_lockq);

	uq->uq_pi_blocked = pi;
	thread_lock(td);
	td->td_flags |= TDF_UPIBLOCKED;
	thread_unlock(td);
	umtx_propagate_priority(td);
	mtx_unlock_spin(&umtx_lock);
	umtxq_unbusy(&uq->uq_key);

	if (uq->uq_flags & UQF_UMTXQ) {
		error = msleep(uq, &uc->uc_lock, PCATCH, wmesg, timo);
		if (error == EWOULDBLOCK)
			error = ETIMEDOUT;
		if (uq->uq_flags & UQF_UMTXQ) {
			umtxq_remove(uq);
		}
	}
	mtx_lock_spin(&umtx_lock);
	uq->uq_pi_blocked = NULL;
	thread_lock(td);
	td->td_flags &= ~TDF_UPIBLOCKED;
	thread_unlock(td);
	TAILQ_REMOVE(&pi->pi_blocked, uq, uq_lockq);
	umtx_unpropagate_priority(pi);
	mtx_unlock_spin(&umtx_lock);
	umtxq_unlock(&uq->uq_key);

	return (error);
}

/*
 * Add reference count for a PI mutex.
 */
static void
umtx_pi_ref(struct umtx_pi *pi)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&pi->pi_key);
	UMTXQ_LOCKED_ASSERT(uc);
	pi->pi_refcount++;
}

/*
 * Decrease reference count for a PI mutex, if the counter
 * is decreased to zero, its memory space is freed.
 */ 
static void
umtx_pi_unref(struct umtx_pi *pi)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&pi->pi_key);
	UMTXQ_LOCKED_ASSERT(uc);
	KASSERT(pi->pi_refcount > 0, ("invalid reference count"));
	if (--pi->pi_refcount == 0) {
		mtx_lock_spin(&umtx_lock);
		if (pi->pi_owner != NULL) {
			TAILQ_REMOVE(&pi->pi_owner->td_umtxq->uq_pi_contested,
				pi, pi_link);
			pi->pi_owner = NULL;
		}
		KASSERT(TAILQ_EMPTY(&pi->pi_blocked),
			("blocked queue not empty"));
		mtx_unlock_spin(&umtx_lock);
		TAILQ_REMOVE(&uc->uc_pi_list, pi, pi_hashlink);
		umtx_pi_free(pi);
	}
}

/*
 * Find a PI mutex in hash table.
 */
static struct umtx_pi *
umtx_pi_lookup(struct umtx_key *key)
{
	struct umtxq_chain *uc;
	struct umtx_pi *pi;

	uc = umtxq_getchain(key);
	UMTXQ_LOCKED_ASSERT(uc);

	TAILQ_FOREACH(pi, &uc->uc_pi_list, pi_hashlink) {
		if (umtx_key_match(&pi->pi_key, key)) {
			return (pi);
		}
	}
	return (NULL);
}

/*
 * Insert a PI mutex into hash table.
 */
static inline void
umtx_pi_insert(struct umtx_pi *pi)
{
	struct umtxq_chain *uc;

	uc = umtxq_getchain(&pi->pi_key);
	UMTXQ_LOCKED_ASSERT(uc);
	TAILQ_INSERT_TAIL(&uc->uc_pi_list, pi, pi_hashlink);
}

/*
 * Lock a PI mutex.
 */
static int
_do_lock_pi(struct thread *td, struct umutex *m, uint32_t flags, int timo,
	int try)
{
	struct umtx_q *uq;
	struct umtx_pi *pi, *new_pi;
	uint32_t id, owner, old;
	int error;

	id = td->td_tid;
	uq = td->td_umtxq;

	if ((error = umtx_key_get(m, TYPE_PI_UMUTEX, GET_SHARE(flags),
	    &uq->uq_key)) != 0)
		return (error);
	umtxq_lock(&uq->uq_key);
	pi = umtx_pi_lookup(&uq->uq_key);
	if (pi == NULL) {
		new_pi = umtx_pi_alloc(M_NOWAIT);
		if (new_pi == NULL) {
			umtxq_unlock(&uq->uq_key);
			new_pi = umtx_pi_alloc(M_WAITOK);
			umtxq_lock(&uq->uq_key);
			pi = umtx_pi_lookup(&uq->uq_key);
			if (pi != NULL) {
				umtx_pi_free(new_pi);
				new_pi = NULL;
			}
		}
		if (new_pi != NULL) {
			new_pi->pi_key = uq->uq_key;
			umtx_pi_insert(new_pi);
			pi = new_pi;
		}
	}
	umtx_pi_ref(pi);
	umtxq_unlock(&uq->uq_key);

	/*
	 * Care must be exercised when dealing with umtx structure.  It
	 * can fault on any access.
	 */
	for (;;) {
		/*
		 * Try the uncontested case.  This should be done in userland.
		 */
		owner = casuword32(&m->m_owner, UMUTEX_UNOWNED, id);

		/* The acquire succeeded. */
		if (owner == UMUTEX_UNOWNED) {
			error = 0;
			break;
		}

		/* The address was invalid. */
		if (owner == -1) {
			error = EFAULT;
			break;
		}

		/* If no one owns it but it is contested try to acquire it. */
		if (owner == UMUTEX_CONTESTED) {
			owner = casuword32(&m->m_owner,
			    UMUTEX_CONTESTED, id | UMUTEX_CONTESTED);

			if (owner == UMUTEX_CONTESTED) {
				umtxq_lock(&uq->uq_key);
				umtxq_busy(&uq->uq_key);
				error = umtx_pi_claim(pi, td);
				umtxq_unbusy(&uq->uq_key);
				umtxq_unlock(&uq->uq_key);
				break;
			}

			/* The address was invalid. */
			if (owner == -1) {
				error = EFAULT;
				break;
			}

			/* If this failed the lock has changed, restart. */
			continue;
		}

		if ((flags & UMUTEX_ERROR_CHECK) != 0 &&
		    (owner & ~UMUTEX_CONTESTED) == id) {
			error = EDEADLK;
			break;
		}

		if (try != 0) {
			error = EBUSY;
			break;
		}

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			break;
			
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		/*
		 * Set the contested bit so that a release in user space
		 * knows to use the system call for unlock.  If this fails
		 * either some one else has acquired the lock or it has been
		 * released.
		 */
		old = casuword32(&m->m_owner, owner, owner | UMUTEX_CONTESTED);

		/* The address was invalid. */
		if (old == -1) {
			umtxq_lock(&uq->uq_key);
			umtxq_unbusy(&uq->uq_key);
			umtxq_unlock(&uq->uq_key);
			error = EFAULT;
			break;
		}

		umtxq_lock(&uq->uq_key);
		/*
		 * We set the contested bit, sleep. Otherwise the lock changed
		 * and we need to retry or we lost a race to the thread
		 * unlocking the umtx.
		 */
		if (old == owner)
			error = umtxq_sleep_pi(uq, pi, owner & ~UMUTEX_CONTESTED,
				 "umtxpi", timo);
		else {
			umtxq_unbusy(&uq->uq_key);
			umtxq_unlock(&uq->uq_key);
		}
	}

	umtxq_lock(&uq->uq_key);
	umtx_pi_unref(pi);
	umtxq_unlock(&uq->uq_key);

	umtx_key_release(&uq->uq_key);
	return (error);
}

/*
 * Unlock a PI mutex.
 */
static int
do_unlock_pi(struct thread *td, struct umutex *m, uint32_t flags)
{
	struct umtx_key key;
	struct umtx_q *uq_first, *uq_first2, *uq_me;
	struct umtx_pi *pi, *pi2;
	uint32_t owner, old, id;
	int error;
	int count;
	int pri;

	id = td->td_tid;
	/*
	 * Make sure we own this mtx.
	 */
	owner = fuword32(__DEVOLATILE(uint32_t *, &m->m_owner));
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMUTEX_CONTESTED) != id)
		return (EPERM);

	/* This should be done in userland */
	if ((owner & UMUTEX_CONTESTED) == 0) {
		old = casuword32(&m->m_owner, owner, UMUTEX_UNOWNED);
		if (old == -1)
			return (EFAULT);
		if (old == owner)
			return (0);
		owner = old;
	}

	/* We should only ever be in here for contested locks */
	if ((error = umtx_key_get(m, TYPE_PI_UMUTEX, GET_SHARE(flags),
	    &key)) != 0)
		return (error);

	umtxq_lock(&key);
	umtxq_busy(&key);
	count = umtxq_count_pi(&key, &uq_first);
	if (uq_first != NULL) {
		mtx_lock_spin(&umtx_lock);
		pi = uq_first->uq_pi_blocked;
		KASSERT(pi != NULL, ("pi == NULL?"));
		if (pi->pi_owner != curthread) {
			mtx_unlock_spin(&umtx_lock);
			umtxq_unbusy(&key);
			umtxq_unlock(&key);
			umtx_key_release(&key);
			/* userland messed the mutex */
			return (EPERM);
		}
		uq_me = curthread->td_umtxq;
		pi->pi_owner = NULL;
		TAILQ_REMOVE(&uq_me->uq_pi_contested, pi, pi_link);
		/* get highest priority thread which is still sleeping. */
		uq_first = TAILQ_FIRST(&pi->pi_blocked);
		while (uq_first != NULL && 
		       (uq_first->uq_flags & UQF_UMTXQ) == 0) {
			uq_first = TAILQ_NEXT(uq_first, uq_lockq);
		}
		pri = PRI_MAX;
		TAILQ_FOREACH(pi2, &uq_me->uq_pi_contested, pi_link) {
			uq_first2 = TAILQ_FIRST(&pi2->pi_blocked);
			if (uq_first2 != NULL) {
				if (pri > UPRI(uq_first2->uq_thread))
					pri = UPRI(uq_first2->uq_thread);
			}
		}
		thread_lock(curthread);
		sched_unlend_user_prio(curthread, pri);
		thread_unlock(curthread);
		mtx_unlock_spin(&umtx_lock);
		if (uq_first)
			umtxq_signal_thread(uq_first);
	}
	umtxq_unlock(&key);

	/*
	 * When unlocking the umtx, it must be marked as unowned if
	 * there is zero or one thread only waiting for it.
	 * Otherwise, it must be marked as contested.
	 */
	old = casuword32(&m->m_owner, owner,
		count <= 1 ? UMUTEX_UNOWNED : UMUTEX_CONTESTED);

	umtxq_lock(&key);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	if (old == -1)
		return (EFAULT);
	if (old != owner)
		return (EINVAL);
	return (0);
}

/*
 * Lock a PP mutex.
 */
static int
_do_lock_pp(struct thread *td, struct umutex *m, uint32_t flags, int timo,
	int try)
{
	struct umtx_q *uq, *uq2;
	struct umtx_pi *pi;
	uint32_t ceiling;
	uint32_t owner, id;
	int error, pri, old_inherited_pri, su;

	id = td->td_tid;
	uq = td->td_umtxq;
	if ((error = umtx_key_get(m, TYPE_PP_UMUTEX, GET_SHARE(flags),
	    &uq->uq_key)) != 0)
		return (error);
	su = (priv_check(td, PRIV_SCHED_RTPRIO) == 0);
	for (;;) {
		old_inherited_pri = uq->uq_inherited_pri;
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		ceiling = RTP_PRIO_MAX - fuword32(&m->m_ceilings[0]);
		if (ceiling > RTP_PRIO_MAX) {
			error = EINVAL;
			goto out;
		}

		mtx_lock_spin(&umtx_lock);
		if (UPRI(td) < PRI_MIN_REALTIME + ceiling) {
			mtx_unlock_spin(&umtx_lock);
			error = EINVAL;
			goto out;
		}
		if (su && PRI_MIN_REALTIME + ceiling < uq->uq_inherited_pri) {
			uq->uq_inherited_pri = PRI_MIN_REALTIME + ceiling;
			thread_lock(td);
			if (uq->uq_inherited_pri < UPRI(td))
				sched_lend_user_prio(td, uq->uq_inherited_pri);
			thread_unlock(td);
		}
		mtx_unlock_spin(&umtx_lock);

		owner = casuword32(&m->m_owner,
		    UMUTEX_CONTESTED, id | UMUTEX_CONTESTED);

		if (owner == UMUTEX_CONTESTED) {
			error = 0;
			break;
		}

		/* The address was invalid. */
		if (owner == -1) {
			error = EFAULT;
			break;
		}

		if ((flags & UMUTEX_ERROR_CHECK) != 0 &&
		    (owner & ~UMUTEX_CONTESTED) == id) {
			error = EDEADLK;
			break;
		}

		if (try != 0) {
			error = EBUSY;
			break;
		}

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			break;

		umtxq_lock(&uq->uq_key);
		umtxq_insert(uq);
		umtxq_unbusy(&uq->uq_key);
		error = umtxq_sleep(uq, "umtxpp", timo);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);

		mtx_lock_spin(&umtx_lock);
		uq->uq_inherited_pri = old_inherited_pri;
		pri = PRI_MAX;
		TAILQ_FOREACH(pi, &uq->uq_pi_contested, pi_link) {
			uq2 = TAILQ_FIRST(&pi->pi_blocked);
			if (uq2 != NULL) {
				if (pri > UPRI(uq2->uq_thread))
					pri = UPRI(uq2->uq_thread);
			}
		}
		if (pri > uq->uq_inherited_pri)
			pri = uq->uq_inherited_pri;
		thread_lock(td);
		sched_unlend_user_prio(td, pri);
		thread_unlock(td);
		mtx_unlock_spin(&umtx_lock);
	}

	if (error != 0) {
		mtx_lock_spin(&umtx_lock);
		uq->uq_inherited_pri = old_inherited_pri;
		pri = PRI_MAX;
		TAILQ_FOREACH(pi, &uq->uq_pi_contested, pi_link) {
			uq2 = TAILQ_FIRST(&pi->pi_blocked);
			if (uq2 != NULL) {
				if (pri > UPRI(uq2->uq_thread))
					pri = UPRI(uq2->uq_thread);
			}
		}
		if (pri > uq->uq_inherited_pri)
			pri = uq->uq_inherited_pri;
		thread_lock(td);
		sched_unlend_user_prio(td, pri);
		thread_unlock(td);
		mtx_unlock_spin(&umtx_lock);
	}

out:
	umtxq_lock(&uq->uq_key);
	umtxq_unbusy(&uq->uq_key);
	umtxq_unlock(&uq->uq_key);
	umtx_key_release(&uq->uq_key);
	return (error);
}

/*
 * Unlock a PP mutex.
 */
static int
do_unlock_pp(struct thread *td, struct umutex *m, uint32_t flags)
{
	struct umtx_key key;
	struct umtx_q *uq, *uq2;
	struct umtx_pi *pi;
	uint32_t owner, id;
	uint32_t rceiling;
	int error, pri, new_inherited_pri, su;

	id = td->td_tid;
	uq = td->td_umtxq;
	su = (priv_check(td, PRIV_SCHED_RTPRIO) == 0);

	/*
	 * Make sure we own this mtx.
	 */
	owner = fuword32(__DEVOLATILE(uint32_t *, &m->m_owner));
	if (owner == -1)
		return (EFAULT);

	if ((owner & ~UMUTEX_CONTESTED) != id)
		return (EPERM);

	error = copyin(&m->m_ceilings[1], &rceiling, sizeof(uint32_t));
	if (error != 0)
		return (error);

	if (rceiling == -1)
		new_inherited_pri = PRI_MAX;
	else {
		rceiling = RTP_PRIO_MAX - rceiling;
		if (rceiling > RTP_PRIO_MAX)
			return (EINVAL);
		new_inherited_pri = PRI_MIN_REALTIME + rceiling;
	}

	if ((error = umtx_key_get(m, TYPE_PP_UMUTEX, GET_SHARE(flags),
	    &key)) != 0)
		return (error);
	umtxq_lock(&key);
	umtxq_busy(&key);
	umtxq_unlock(&key);
	/*
	 * For priority protected mutex, always set unlocked state
	 * to UMUTEX_CONTESTED, so that userland always enters kernel
	 * to lock the mutex, it is necessary because thread priority
	 * has to be adjusted for such mutex.
	 */
	error = suword32(__DEVOLATILE(uint32_t *, &m->m_owner),
		UMUTEX_CONTESTED);

	umtxq_lock(&key);
	if (error == 0)
		umtxq_signal(&key, 1);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);

	if (error == -1)
		error = EFAULT;
	else {
		mtx_lock_spin(&umtx_lock);
		if (su != 0)
			uq->uq_inherited_pri = new_inherited_pri;
		pri = PRI_MAX;
		TAILQ_FOREACH(pi, &uq->uq_pi_contested, pi_link) {
			uq2 = TAILQ_FIRST(&pi->pi_blocked);
			if (uq2 != NULL) {
				if (pri > UPRI(uq2->uq_thread))
					pri = UPRI(uq2->uq_thread);
			}
		}
		if (pri > uq->uq_inherited_pri)
			pri = uq->uq_inherited_pri;
		thread_lock(td);
		sched_unlend_user_prio(td, pri);
		thread_unlock(td);
		mtx_unlock_spin(&umtx_lock);
	}
	umtx_key_release(&key);
	return (error);
}
#endif

static int
do_set_ceiling(struct thread *td, struct umutex *m, uint32_t ceiling,
	uint32_t *old_ceiling)
{
	struct umtx_q *uq;
	uint32_t save_ceiling;
	uint32_t owner, id;
	uint32_t flags;
	int error;

	flags = fuword32(&m->m_flags);
	if ((flags & UMUTEX_PRIO_PROTECT) == 0)
		return (EINVAL);
	if (ceiling > RTP_PRIO_MAX)
		return (EINVAL);
	id = td->td_tid;
	uq = td->td_umtxq;
	if ((error = umtx_key_get(m, TYPE_PP_UMUTEX, GET_SHARE(flags),
	   &uq->uq_key)) != 0)
		return (error);
	for (;;) {
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		save_ceiling = fuword32(&m->m_ceilings[0]);

		owner = casuword32(&m->m_owner,
		    UMUTEX_CONTESTED, id | UMUTEX_CONTESTED);

		if (owner == UMUTEX_CONTESTED) {
			suword32(&m->m_ceilings[0], ceiling);
			suword32(__DEVOLATILE(uint32_t *, &m->m_owner),
				UMUTEX_CONTESTED);
			error = 0;
			break;
		}

		/* The address was invalid. */
		if (owner == -1) {
			error = EFAULT;
			break;
		}

		if ((owner & ~UMUTEX_CONTESTED) == id) {
			suword32(&m->m_ceilings[0], ceiling);
			error = 0;
			break;
		}

		/*
		 * If we caught a signal, we have retried and now
		 * exit immediately.
		 */
		if (error != 0)
			break;

		/*
		 * We set the contested bit, sleep. Otherwise the lock changed
		 * and we need to retry or we lost a race to the thread
		 * unlocking the umtx.
		 */
		umtxq_lock(&uq->uq_key);
		umtxq_insert(uq);
		umtxq_unbusy(&uq->uq_key);
		error = umtxq_sleep(uq, "umtxpp", 0);
		umtxq_remove(uq);
		umtxq_unlock(&uq->uq_key);
	}
	umtxq_lock(&uq->uq_key);
	if (error == 0)
		umtxq_signal(&uq->uq_key, INT_MAX);
	umtxq_unbusy(&uq->uq_key);
	umtxq_unlock(&uq->uq_key);
	umtx_key_release(&uq->uq_key);
	if (error == 0 && old_ceiling != NULL)
		suword32(old_ceiling, save_ceiling);
	return (error);
}

static int
_do_lock_umutex(struct thread *td, struct umutex *m, int flags, int timo,
	int mode)
{
	switch(flags & (UMUTEX_PRIO_INHERIT | UMUTEX_PRIO_PROTECT)) {
	case UMUTEX_PRIO_INHERIT:
#ifndef __AVM2__
		return (_do_lock_pi(td, m, flags, timo, mode));
#endif
	case UMUTEX_PRIO_PROTECT:
#ifndef __AVM2__
		return (_do_lock_pp(td, m, flags, timo, mode));
#endif
	case 0:
		return (_do_lock_normal(td, m, flags, timo, mode));
	}
	return (EINVAL);
}

/*
 * Lock a userland POSIX mutex.
 */
static int
do_lock_umutex(struct thread *td, struct umutex *m,
	struct timespec *timeout, int mode)
{
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	uint32_t flags;
	int error;

	flags = fuword32(&m->m_flags);
	if (flags == -1)
		return (EFAULT);

	if (timeout == NULL) {
		error = _do_lock_umutex(td, m, flags, 0, mode);
		/* Mutex locking is restarted if it is interrupted. */
		if (error == EINTR && mode != _UMUTEX_WAIT)
			error = ERESTART;
	} else {
		getnanouptime(&ts);
		timespecadd(&ts, timeout);
		TIMESPEC_TO_TIMEVAL(&tv, timeout);
		for (;;) {
			error = _do_lock_umutex(td, m, flags, tvtohz(&tv), mode);
			if (error != ETIMEDOUT)
				break;
			getnanouptime(&ts2);
			if (timespeccmp(&ts2, &ts, >=)) {
				error = ETIMEDOUT;
				break;
			}
			ts3 = ts;
			timespecsub(&ts3, &ts2);
			TIMESPEC_TO_TIMEVAL(&tv, &ts3);
		}
		/* Timed-locking is not restarted. */
		if (error == ERESTART)
			error = EINTR;
	}
	return (error);
}

/*
 * Unlock a userland POSIX mutex.
 */
static int
do_unlock_umutex(struct thread *td, struct umutex *m)
{
	uint32_t flags;

	flags = fuword32(&m->m_flags);
	if (flags == -1)
		return (EFAULT);

	switch(flags & (UMUTEX_PRIO_INHERIT | UMUTEX_PRIO_PROTECT)) {
	case UMUTEX_PRIO_INHERIT:
#ifndef __AVM2__
		return (do_unlock_pi(td, m, flags));
#endif
	case UMUTEX_PRIO_PROTECT:
#ifndef __AVM2__
		return (do_unlock_pp(td, m, flags));
#endif
	case 0:
		return (do_unlock_normal(td, m, flags));
	}

	return (EINVAL);
}

static int
do_cv_wait(struct thread *td, struct ucond *cv, struct umutex *m,
	struct timespec *timeout, u_long wflags)
{
	struct umtx_q *uq;
	struct timeval tv;
	struct timespec cts, ets, tts;
	uint32_t flags;
	int error;

	uq = td->td_umtxq;
	flags = fuword32(&cv->c_flags);
	error = umtx_key_get(cv, TYPE_CV, GET_SHARE(flags), &uq->uq_key);
	if (error != 0)
		return (error);
	umtxq_lock(&uq->uq_key);
	umtxq_busy(&uq->uq_key);
	umtxq_insert(uq);
	umtxq_unlock(&uq->uq_key);

	/*
	 * The magic thing is we should set c_has_waiters to 1 before
	 * releasing user mutex.
	 */
	suword32(__DEVOLATILE(uint32_t *, &cv->c_has_waiters), 1);

	umtxq_lock(&uq->uq_key);
	umtxq_unbusy(&uq->uq_key);
	umtxq_unlock(&uq->uq_key);

	error = do_unlock_umutex(td, m);
	
	umtxq_lock(&uq->uq_key);
	if (error == 0) {
		if ((wflags & UMTX_CHECK_UNPARKING) &&
		    (td->td_pflags & TDP_WAKEUP)) {
			td->td_pflags &= ~TDP_WAKEUP;
			error = EINTR;
		} else if (timeout == NULL) {
			error = umtxq_sleep(uq, "ucond", 0);
		} else {
			getnanouptime(&ets);
			timespecadd(&ets, timeout);
			TIMESPEC_TO_TIMEVAL(&tv, timeout);
			for (;;) {
				error = umtxq_sleep(uq, "ucond", tvtohz(&tv));
				if (error != ETIMEDOUT)
					break;
				getnanouptime(&cts);
				if (timespeccmp(&cts, &ets, >=)) {
					error = ETIMEDOUT;
					break;
				}
				tts = ets;
				timespecsub(&tts, &cts);
				TIMESPEC_TO_TIMEVAL(&tv, &tts);
			}
		}
	}

	if (error != 0) {
		if ((uq->uq_flags & UQF_UMTXQ) == 0) {
			/*
			 * If we concurrently got do_cv_signal()d
			 * and we got an error or UNIX signals or a timeout,
			 * then, perform another umtxq_signal to avoid
			 * consuming the wakeup. This may cause supurious
			 * wakeup for another thread which was just queued,
			 * but SUSV3 explicitly allows supurious wakeup to
			 * occur, and indeed a kernel based implementation
			 * can not avoid it.
			 */ 
			if (!umtxq_signal(&uq->uq_key, 1))
				error = 0;
		}
		if (error == ERESTART)
			error = EINTR;
	}
	umtxq_remove(uq);
	umtxq_unlock(&uq->uq_key);
	umtx_key_release(&uq->uq_key);
	return (error);
}

/*
 * Signal a userland condition variable.
 */
static int
do_cv_signal(struct thread *td, struct ucond *cv)
{
	struct umtx_key key;
	int error, cnt, nwake;
	uint32_t flags;

	flags = fuword32(&cv->c_flags);
	if ((error = umtx_key_get(cv, TYPE_CV, GET_SHARE(flags), &key)) != 0)
		return (error);	
	umtxq_lock(&key);
	umtxq_busy(&key);
	cnt = umtxq_count(&key);
	nwake = umtxq_signal(&key, 1);
	if (cnt <= nwake) {
		umtxq_unlock(&key);
		error = suword32(
		    __DEVOLATILE(uint32_t *, &cv->c_has_waiters), 0);
		umtxq_lock(&key);
	}
	umtxq_unbusy(&key);
	umtxq_unlock(&key);
	umtx_key_release(&key);
	return (error);
}

static int
do_cv_broadcast(struct thread *td, struct ucond *cv)
{
	struct umtx_key key;
	int error;
	uint32_t flags;

	flags = fuword32(&cv->c_flags);
	if ((error = umtx_key_get(cv, TYPE_CV, GET_SHARE(flags), &key)) != 0)
		return (error);	

	umtxq_lock(&key);
	umtxq_busy(&key);
	umtxq_signal(&key, INT_MAX);
	umtxq_unlock(&key);

	error = suword32(__DEVOLATILE(uint32_t *, &cv->c_has_waiters), 0);

	umtxq_lock(&key);
	umtxq_unbusy(&key);
	umtxq_unlock(&key);

	umtx_key_release(&key);
	return (error);
}

static int
do_rw_rdlock(struct thread *td, struct urwlock *rwlock, long fflag, int timo)
{
	struct umtx_q *uq;
	uint32_t flags, wrflags;
	int32_t state, oldstate;
	int32_t blocked_readers;
	int error;

	uq = td->td_umtxq;
	flags = fuword32(&rwlock->rw_flags);
	error = umtx_key_get(rwlock, TYPE_RWLOCK, GET_SHARE(flags), &uq->uq_key);
	if (error != 0)
		return (error);

	wrflags = URWLOCK_WRITE_OWNER;
	if (!(fflag & URWLOCK_PREFER_READER) && !(flags & URWLOCK_PREFER_READER))
		wrflags |= URWLOCK_WRITE_WAITERS;

	for (;;) {
		state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
		/* try to lock it */
		while (!(state & wrflags)) {
			if (__predict_false(URWLOCK_READER_COUNT(state) == URWLOCK_MAX_READERS)) {
				umtx_key_release(&uq->uq_key);
				return (EAGAIN);
			}
			oldstate = casuword32(&rwlock->rw_state, state, state + 1);
			if (oldstate == state) {
				umtx_key_release(&uq->uq_key);
				return (0);
			}
			state = oldstate;
		}

		if (error)
			break;

		/* grab monitor lock */
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		/*
		 * re-read the state, in case it changed between the try-lock above
		 * and the check below
		 */
		state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));

		/* set read contention bit */
		while ((state & wrflags) && !(state & URWLOCK_READ_WAITERS)) {
			oldstate = casuword32(&rwlock->rw_state, state, state | URWLOCK_READ_WAITERS);
			if (oldstate == state)
				goto sleep;
			state = oldstate;
		}

		/* state is changed while setting flags, restart */
		if (!(state & wrflags)) {
			umtxq_lock(&uq->uq_key);
			umtxq_unbusy(&uq->uq_key);
			umtxq_unlock(&uq->uq_key);
			continue;
		}

sleep:
		/* contention bit is set, before sleeping, increase read waiter count */
		blocked_readers = fuword32(&rwlock->rw_blocked_readers);
		suword32(&rwlock->rw_blocked_readers, blocked_readers+1);

		while (state & wrflags) {
			umtxq_lock(&uq->uq_key);
			umtxq_insert(uq);
			umtxq_unbusy(&uq->uq_key);

			error = umtxq_sleep(uq, "urdlck", timo);

			umtxq_busy(&uq->uq_key);
			umtxq_remove(uq);
			umtxq_unlock(&uq->uq_key);
			if (error)
				break;
			state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
		}

		/* decrease read waiter count, and may clear read contention bit */
		blocked_readers = fuword32(&rwlock->rw_blocked_readers);
		suword32(&rwlock->rw_blocked_readers, blocked_readers-1);
		if (blocked_readers == 1) {
			state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
			for (;;) {
				oldstate = casuword32(&rwlock->rw_state, state,
					 state & ~URWLOCK_READ_WAITERS);
				if (oldstate == state)
					break;
				state = oldstate;
			}
		}

		umtxq_lock(&uq->uq_key);
		umtxq_unbusy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);
	}
	umtx_key_release(&uq->uq_key);
	return (error);
}

static int
do_rw_rdlock2(struct thread *td, void *obj, long val, struct timespec *timeout)
{
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	int error;

	getnanouptime(&ts);
	timespecadd(&ts, timeout);
	TIMESPEC_TO_TIMEVAL(&tv, timeout);
	for (;;) {
		error = do_rw_rdlock(td, obj, val, tvtohz(&tv));
		if (error != ETIMEDOUT)
			break;
		getnanouptime(&ts2);
		if (timespeccmp(&ts2, &ts, >=)) {
			error = ETIMEDOUT;
			break;
		}
		ts3 = ts;
		timespecsub(&ts3, &ts2);
		TIMESPEC_TO_TIMEVAL(&tv, &ts3);
	}
	if (error == ERESTART)
		error = EINTR;
	return (error);
}

static int
do_rw_wrlock(struct thread *td, struct urwlock *rwlock, int timo)
{
	struct umtx_q *uq;
	uint32_t flags;
	int32_t state, oldstate;
	int32_t blocked_writers;
	int32_t blocked_readers;
	int error;

	uq = td->td_umtxq;
	flags = fuword32(&rwlock->rw_flags);
	error = umtx_key_get(rwlock, TYPE_RWLOCK, GET_SHARE(flags), &uq->uq_key);
	if (error != 0)
		return (error);

	blocked_readers = 0;
	for (;;) {
		state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
		while (!(state & URWLOCK_WRITE_OWNER) && URWLOCK_READER_COUNT(state) == 0) {
			oldstate = casuword32(&rwlock->rw_state, state, state | URWLOCK_WRITE_OWNER);
			if (oldstate == state) {
				umtx_key_release(&uq->uq_key);
				return (0);
			}
			state = oldstate;
		}

		if (error) {
			if (!(state & (URWLOCK_WRITE_OWNER|URWLOCK_WRITE_WAITERS)) &&
			    blocked_readers != 0) {
				umtxq_lock(&uq->uq_key);
				umtxq_busy(&uq->uq_key);
				umtxq_signal_queue(&uq->uq_key, INT_MAX, UMTX_SHARED_QUEUE);
				umtxq_unbusy(&uq->uq_key);
				umtxq_unlock(&uq->uq_key);
			}

			break;
		}

		/* grab monitor lock */
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);

		/*
		 * re-read the state, in case it changed between the try-lock above
		 * and the check below
		 */
		state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));

		while (((state & URWLOCK_WRITE_OWNER) || URWLOCK_READER_COUNT(state) != 0) &&
		       (state & URWLOCK_WRITE_WAITERS) == 0) {
			oldstate = casuword32(&rwlock->rw_state, state, state | URWLOCK_WRITE_WAITERS);
			if (oldstate == state)
				goto sleep;
			state = oldstate;
		}

		if (!(state & URWLOCK_WRITE_OWNER) && URWLOCK_READER_COUNT(state) == 0) {
			umtxq_lock(&uq->uq_key);
			umtxq_unbusy(&uq->uq_key);
			umtxq_unlock(&uq->uq_key);
			continue;
		}
sleep:
		blocked_writers = fuword32(&rwlock->rw_blocked_writers);
		suword32(&rwlock->rw_blocked_writers, blocked_writers+1);

		while ((state & URWLOCK_WRITE_OWNER) || URWLOCK_READER_COUNT(state) != 0) {
			umtxq_lock(&uq->uq_key);
			umtxq_insert_queue(uq, UMTX_EXCLUSIVE_QUEUE);
			umtxq_unbusy(&uq->uq_key);

			error = umtxq_sleep(uq, "uwrlck", timo);

			umtxq_busy(&uq->uq_key);
			umtxq_remove_queue(uq, UMTX_EXCLUSIVE_QUEUE);
			umtxq_unlock(&uq->uq_key);
			if (error)
				break;
			state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
		}

		blocked_writers = fuword32(&rwlock->rw_blocked_writers);
		suword32(&rwlock->rw_blocked_writers, blocked_writers-1);
		if (blocked_writers == 1) {
			state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
			for (;;) {
				oldstate = casuword32(&rwlock->rw_state, state,
					 state & ~URWLOCK_WRITE_WAITERS);
				if (oldstate == state)
					break;
				state = oldstate;
			}
			blocked_readers = fuword32(&rwlock->rw_blocked_readers);
		} else
			blocked_readers = 0;

		umtxq_lock(&uq->uq_key);
		umtxq_unbusy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);
	}

	umtx_key_release(&uq->uq_key);
	return (error);
}

static int
do_rw_wrlock2(struct thread *td, void *obj, struct timespec *timeout)
{
	struct timespec ts, ts2, ts3;
	struct timeval tv;
	int error;

	getnanouptime(&ts);
	timespecadd(&ts, timeout);
	TIMESPEC_TO_TIMEVAL(&tv, timeout);
	for (;;) {
		error = do_rw_wrlock(td, obj, tvtohz(&tv));
		if (error != ETIMEDOUT)
			break;
		getnanouptime(&ts2);
		if (timespeccmp(&ts2, &ts, >=)) {
			error = ETIMEDOUT;
			break;
		}
		ts3 = ts;
		timespecsub(&ts3, &ts2);
		TIMESPEC_TO_TIMEVAL(&tv, &ts3);
	}
	if (error == ERESTART)
		error = EINTR;
	return (error);
}

static int
do_rw_unlock(struct thread *td, struct urwlock *rwlock)
{
	struct umtx_q *uq;
	uint32_t flags;
	int32_t state, oldstate;
	int error, q, count;

	uq = td->td_umtxq;
	flags = fuword32(&rwlock->rw_flags);
	error = umtx_key_get(rwlock, TYPE_RWLOCK, GET_SHARE(flags), &uq->uq_key);
	if (error != 0)
		return (error);

	state = fuword32(__DEVOLATILE(int32_t *, &rwlock->rw_state));
	if (state & URWLOCK_WRITE_OWNER) {
		for (;;) {
			oldstate = casuword32(&rwlock->rw_state, state, 
				state & ~URWLOCK_WRITE_OWNER);
			if (oldstate != state) {
				state = oldstate;
				if (!(oldstate & URWLOCK_WRITE_OWNER)) {
					error = EPERM;
					goto out;
				}
			} else
				break;
		}
	} else if (URWLOCK_READER_COUNT(state) != 0) {
		for (;;) {
			oldstate = casuword32(&rwlock->rw_state, state,
				state - 1);
			if (oldstate != state) {
				state = oldstate;
				if (URWLOCK_READER_COUNT(oldstate) == 0) {
					error = EPERM;
					goto out;
				}
			}
			else
				break;
		}
	} else {
		error = EPERM;
		goto out;
	}

	count = 0;

	if (!(flags & URWLOCK_PREFER_READER)) {
		if (state & URWLOCK_WRITE_WAITERS) {
			count = 1;
			q = UMTX_EXCLUSIVE_QUEUE;
		} else if (state & URWLOCK_READ_WAITERS) {
			count = INT_MAX;
			q = UMTX_SHARED_QUEUE;
		}
	} else {
		if (state & URWLOCK_READ_WAITERS) {
			count = INT_MAX;
			q = UMTX_SHARED_QUEUE;
		} else if (state & URWLOCK_WRITE_WAITERS) {
			count = 1;
			q = UMTX_EXCLUSIVE_QUEUE;
		}
	}

	if (count) {
		umtxq_lock(&uq->uq_key);
		umtxq_busy(&uq->uq_key);
		umtxq_signal_queue(&uq->uq_key, count, q);
		umtxq_unbusy(&uq->uq_key);
		umtxq_unlock(&uq->uq_key);
	}
out:
	umtx_key_release(&uq->uq_key);
	return (error);
}

int
_umtx_lock(struct thread *td, struct _umtx_lock_args *uap)
    /* struct umtx *umtx */
{
	return _do_lock_umtx(td, uap->umtx, td->td_tid, 0);
}

int
_umtx_unlock(struct thread *td, struct _umtx_unlock_args *uap)
    /* struct umtx *umtx */
{
	return do_unlock_umtx(td, uap->umtx, td->td_tid);
}

static int
__umtx_op_lock_umtx(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout, sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		ts = &timeout;
	}
	return (do_lock_umtx(td, uap->obj, uap->val, ts));
}

static int
__umtx_op_unlock_umtx(struct thread *td, struct _umtx_op_args *uap)
{
	return (do_unlock_umtx(td, uap->obj, uap->val));
}

static int
__umtx_op_wait(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout, sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_wait(td, uap->obj, uap->val, ts, 0, 0);
}

static int
__umtx_op_wait_uint(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout, sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_wait(td, uap->obj, uap->val, ts, 1, 0);
}

static int
__umtx_op_wait_uint_private(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout, sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_wait(td, uap->obj, uap->val, ts, 1, 1);
}

static int
__umtx_op_wake(struct thread *td, struct _umtx_op_args *uap)
{
	return (kern_umtx_wake(td, uap->obj, uap->val, 0));
}

static int
__umtx_op_wake_private(struct thread *td, struct _umtx_op_args *uap)
{
	return (kern_umtx_wake(td, uap->obj, uap->val, 1));
}

static int
__umtx_op_lock_umutex(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		ts = &timeout;
	}
	return do_lock_umutex(td, uap->obj, ts, 0);
}

static int
__umtx_op_trylock_umutex(struct thread *td, struct _umtx_op_args *uap)
{
	return do_lock_umutex(td, uap->obj, NULL, _UMUTEX_TRY);
}

static int
__umtx_op_wait_umutex(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		ts = &timeout;
	}
	return do_lock_umutex(td, uap->obj, ts, _UMUTEX_WAIT);
}

static int
__umtx_op_wake_umutex(struct thread *td, struct _umtx_op_args *uap)
{
	return do_wake_umutex(td, uap->obj);
}

static int
__umtx_op_unlock_umutex(struct thread *td, struct _umtx_op_args *uap)
{
	return do_unlock_umutex(td, uap->obj);
}

static int
__umtx_op_set_ceiling(struct thread *td, struct _umtx_op_args *uap)
{
	return do_set_ceiling(td, uap->obj, uap->val, uap->uaddr1);
}

static int
__umtx_op_cv_wait(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		ts = &timeout;
	}
	return (do_cv_wait(td, uap->obj, uap->uaddr1, ts, uap->val));
}

static int
__umtx_op_cv_signal(struct thread *td, struct _umtx_op_args *uap)
{
	return do_cv_signal(td, uap->obj);
}

static int
__umtx_op_cv_broadcast(struct thread *td, struct _umtx_op_args *uap)
{
	return do_cv_broadcast(td, uap->obj);
}

static int
__umtx_op_rw_rdlock(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL) {
		error = do_rw_rdlock(td, uap->obj, uap->val, 0);
	} else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		error = do_rw_rdlock2(td, uap->obj, uap->val, &timeout);
	}
	return (error);
}

static int
__umtx_op_rw_wrlock(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL) {
		error = do_rw_wrlock(td, uap->obj, 0);
	} else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}

		error = do_rw_wrlock2(td, uap->obj, &timeout);
	}
	return (error);
}

static int
__umtx_op_rw_unlock(struct thread *td, struct _umtx_op_args *uap)
{
	return do_rw_unlock(td, uap->obj);
}

typedef int (*_umtx_op_func)(struct thread *td, struct _umtx_op_args *uap);

static _umtx_op_func op_table[] = {
	__umtx_op_lock_umtx,		/* UMTX_OP_LOCK */
	__umtx_op_unlock_umtx,		/* UMTX_OP_UNLOCK */
	__umtx_op_wait,			/* UMTX_OP_WAIT */
	__umtx_op_wake,			/* UMTX_OP_WAKE */
	__umtx_op_trylock_umutex,	/* UMTX_OP_MUTEX_TRYLOCK */
	__umtx_op_lock_umutex,		/* UMTX_OP_MUTEX_LOCK */
	__umtx_op_unlock_umutex,	/* UMTX_OP_MUTEX_UNLOCK */
	__umtx_op_set_ceiling,		/* UMTX_OP_SET_CEILING */
	__umtx_op_cv_wait,		/* UMTX_OP_CV_WAIT*/
	__umtx_op_cv_signal,		/* UMTX_OP_CV_SIGNAL */
	__umtx_op_cv_broadcast,		/* UMTX_OP_CV_BROADCAST */
	__umtx_op_wait_uint,		/* UMTX_OP_WAIT_UINT */
	__umtx_op_rw_rdlock,		/* UMTX_OP_RW_RDLOCK */
	__umtx_op_rw_wrlock,		/* UMTX_OP_RW_WRLOCK */
	__umtx_op_rw_unlock,		/* UMTX_OP_RW_UNLOCK */
	/*15*/__umtx_op_wait_uint_private,	/* UMTX_OP_WAIT_UINT_PRIVATE */
	/*16*/__umtx_op_wake_private,		/* UMTX_OP_WAKE_PRIVATE */
	/*17*/__umtx_op_wait_umutex,		/* UMTX_OP_UMUTEX_WAIT */
	/*18*/__umtx_op_wake_umutex		/* UMTX_OP_UMUTEX_WAKE */
};

int
_umtx_op(struct thread *td, struct _umtx_op_args *uap)
{
	if ((unsigned)uap->op < UMTX_OP_MAX)
		return (*op_table[uap->op])(td, uap);
	return (EINVAL);
}

#ifdef COMPAT_FREEBSD32
int
freebsd32_umtx_lock(struct thread *td, struct freebsd32_umtx_lock_args *uap)
    /* struct umtx *umtx */
{
	return (do_lock_umtx32(td, (uint32_t *)uap->umtx, td->td_tid, NULL));
}

int
freebsd32_umtx_unlock(struct thread *td, struct freebsd32_umtx_unlock_args *uap)
    /* struct umtx *umtx */
{
	return (do_unlock_umtx32(td, (uint32_t *)uap->umtx, td->td_tid));
}

struct timespec32 {
	u_int32_t tv_sec;
	u_int32_t tv_nsec;
};

static inline int
copyin_timeout32(void *addr, struct timespec *tsp)
{
	struct timespec32 ts32;
	int error;

	error = copyin(addr, &ts32, sizeof(struct timespec32));
	if (error == 0) {
		tsp->tv_sec = ts32.tv_sec;
		tsp->tv_nsec = ts32.tv_nsec;
	}
	return (error);
}

static int
__umtx_op_lock_umtx_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		ts = &timeout;
	}
	return (do_lock_umtx32(td, uap->obj, uap->val, ts));
}

static int
__umtx_op_unlock_umtx_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	return (do_unlock_umtx32(td, uap->obj, (uint32_t)uap->val));
}

static int
__umtx_op_wait_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_wait(td, uap->obj, uap->val, ts, 1, 0);
}

static int
__umtx_op_lock_umutex_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_lock_umutex(td, uap->obj, ts, 0);
}

static int
__umtx_op_wait_umutex_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_lock_umutex(td, uap->obj, ts, _UMUTEX_WAIT);
}

static int
__umtx_op_cv_wait_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return (do_cv_wait(td, uap->obj, uap->uaddr1, ts, uap->val));
}

static int
__umtx_op_rw_rdlock_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL) {
		error = do_rw_rdlock(td, uap->obj, uap->val, 0);
	} else {
		error = copyin(uap->uaddr2, &timeout,
		    sizeof(timeout));
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}
		error = do_rw_rdlock2(td, uap->obj, uap->val, &timeout);
	}
	return (error);
}

static int
__umtx_op_rw_wrlock_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec timeout;
	int error;

	/* Allow a null timespec (wait forever). */
	if (uap->uaddr2 == NULL) {
		error = do_rw_wrlock(td, uap->obj, 0);
	} else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0) {
			return (EINVAL);
		}

		error = do_rw_wrlock2(td, uap->obj, &timeout);
	}
	return (error);
}

static int
__umtx_op_wait_uint_private_compat32(struct thread *td, struct _umtx_op_args *uap)
{
	struct timespec *ts, timeout;
	int error;

	if (uap->uaddr2 == NULL)
		ts = NULL;
	else {
		error = copyin_timeout32(uap->uaddr2, &timeout);
		if (error != 0)
			return (error);
		if (timeout.tv_nsec >= 1000000000 ||
		    timeout.tv_nsec < 0)
			return (EINVAL);
		ts = &timeout;
	}
	return do_wait(td, uap->obj, uap->val, ts, 1, 1);
}

static _umtx_op_func op_table_compat32[] = {
	__umtx_op_lock_umtx_compat32,	/* UMTX_OP_LOCK */
	__umtx_op_unlock_umtx_compat32,	/* UMTX_OP_UNLOCK */
	__umtx_op_wait_compat32,	/* UMTX_OP_WAIT */
	__umtx_op_wake,			/* UMTX_OP_WAKE */
	__umtx_op_trylock_umutex,	/* UMTX_OP_MUTEX_LOCK */
	__umtx_op_lock_umutex_compat32,	/* UMTX_OP_MUTEX_TRYLOCK */
	__umtx_op_unlock_umutex,	/* UMTX_OP_MUTEX_UNLOCK	*/
	__umtx_op_set_ceiling,		/* UMTX_OP_SET_CEILING */
	__umtx_op_cv_wait_compat32,	/* UMTX_OP_CV_WAIT*/
	__umtx_op_cv_signal,		/* UMTX_OP_CV_SIGNAL */
	__umtx_op_cv_broadcast,		/* UMTX_OP_CV_BROADCAST */
	__umtx_op_wait_compat32,	/* UMTX_OP_WAIT_UINT */
	__umtx_op_rw_rdlock_compat32,	/* UMTX_OP_RW_RDLOCK */
	__umtx_op_rw_wrlock_compat32,	/* UMTX_OP_RW_WRLOCK */
	__umtx_op_rw_unlock,		/* UMTX_OP_RW_UNLOCK */
	__umtx_op_wait_uint_private_compat32,	/* UMTX_OP_WAIT_UINT_PRIVATE */
	__umtx_op_wake_private,		/* UMTX_OP_WAKE_PRIVATE */
	__umtx_op_wait_umutex_compat32, /* UMTX_OP_UMUTEX_WAIT */
	__umtx_op_wake_umutex		/* UMTX_OP_UMUTEX_WAKE */
};

int
freebsd32_umtx_op(struct thread *td, struct freebsd32_umtx_op_args *uap)
{
	if ((unsigned)uap->op < UMTX_OP_MAX)
		return (*op_table_compat32[uap->op])(td,
			(struct _umtx_op_args *)uap);
	return (EINVAL);
}
#endif

void
umtx_thread_init(struct thread *td)
{
	td->td_umtxq = umtxq_alloc();
	td->td_umtxq->uq_thread = td;
}

void
umtx_thread_fini(struct thread *td)
{
	umtxq_free(td->td_umtxq);
}

/*
 * It will be called when new thread is created, e.g fork().
 */
void
umtx_thread_alloc(struct thread *td)
{
	struct umtx_q *uq;

	uq = td->td_umtxq;
	uq->uq_inherited_pri = PRI_MAX;

	KASSERT(uq->uq_flags == 0, ("uq_flags != 0"));
	KASSERT(uq->uq_thread == td, ("uq_thread != td"));
	KASSERT(uq->uq_pi_blocked == NULL, ("uq_pi_blocked != NULL"));
	KASSERT(TAILQ_EMPTY(&uq->uq_pi_contested), ("uq_pi_contested is not empty"));
}

/*
 * exec() hook.
 */
static void
umtx_exec_hook(void *arg __unused, struct proc *p __unused,
	struct image_params *imgp __unused)
{
	umtx_thread_cleanup(curthread);
}

/*
 * thread_exit() hook.
 */
void
umtx_thread_exit(struct thread *td)
{
	umtx_thread_cleanup(td);
}

/*
 * clean up umtx data.
 */
static void
umtx_thread_cleanup(struct thread *td)
{
	struct umtx_q *uq;
#ifndef __AVM2__
	struct umtx_pi *pi;
#endif

	if ((uq = td->td_umtxq) == NULL)
		return;

	mtx_lock_spin(&umtx_lock);
	uq->uq_inherited_pri = PRI_MAX;
#ifndef __AVM2__
	while ((pi = TAILQ_FIRST(&uq->uq_pi_contested)) != NULL) {
		pi->pi_owner = NULL;
		TAILQ_REMOVE(&uq->uq_pi_contested, pi, pi_link);
	}
#endif
	thread_lock(td);
	td->td_flags &= ~TDF_UBORROWING;
	thread_unlock(td);
	mtx_unlock_spin(&umtx_lock);
}
