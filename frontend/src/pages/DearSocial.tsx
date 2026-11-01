import { useEffect } from 'react';
import { useLocation, useParams } from 'react-router-dom';

// The complete Moment UI is shipped from Linko in the same release and origin.
export default function DearSocialPage() {
  const location = useLocation();
  const { spaceId, activityId } = useParams();
  useEffect(() => {
    const query = new URLSearchParams(location.search);
    if (spaceId && activityId) { query.set('space', spaceId); query.set('activity', activityId); }
    window.location.replace('/moment/' + (query.size ? '?' + query.toString() : ''));
  }, [location.search, spaceId, activityId]);
  return <p className="p-6 text-slate-600">正在打开活动与照片分享…</p>;
}
