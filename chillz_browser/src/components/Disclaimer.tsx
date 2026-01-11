
import { AlertTriangle, Shield, ExternalLink } from 'lucide-react';
import './Disclaimer.css';

interface DisclaimerProps {
  onAccept: () => void;
}

export function Disclaimer({ onAccept }: DisclaimerProps) {
  return (
    <div className="disclaimer">
      <div className="disclaimer__card">
        <div className="disclaimer__icon">
          <Shield size={48} />
        </div>
        
        <h1 className="disclaimer__title">
          <span className="disclaimer__logo">📺</span>
          Chillz
        </h1>
        <p className="disclaimer__tagline">TV, but Chill</p>

        <div className="disclaimer__content">
          <div className="disclaimer__warning">
            <AlertTriangle size={20} />
            <span>Please read before continuing</span>
          </div>

          <div className="disclaimer__text">
            <h3>About This App</h3>
            <p>
              Chillz is a <strong>client-side only</strong> web application that helps you 
              browse and play publicly available IPTV streams directly in your browser.
            </p>

            <h3>Important Information</h3>
            <ul>
              <li>
                <strong>No Proxy/Relay:</strong> This app does not proxy, relay, or restream 
                any content. All streams are played directly from their source URLs.
              </li>
              <li>
                <strong>Browser Playback Only:</strong> Streams play directly in your browser. 
                Some streams may not work due to CORS restrictions, DRM protection, or 
                format incompatibility.
              </li>
              <li>
                <strong>Public Streams:</strong> This app only references publicly available 
                streams. It does not bypass any DRM or access restrictions.
              </li>
              <li>
                <strong>User Responsibility:</strong> You are responsible for ensuring that 
                your use of any streams complies with local laws and the terms of service 
                of the stream providers.
              </li>
              <li>
                <strong>No Guarantees:</strong> Stream availability and quality depend 
                entirely on the source providers. Streams may go offline at any time.
              </li>
            </ul>

            <h3>Privacy</h3>
            <p>
              This app runs entirely in your browser. No data is sent to any server. 
              Your preferences and history are stored locally on your device.
            </p>
          </div>
        </div>

        <div className="disclaimer__actions">
          <button className="disclaimer__btn" onClick={onAccept}>
            I Understand, Continue
          </button>
          <a 
            href="https://github.com/iptv-org/iptv" 
            target="_blank" 
            rel="noopener noreferrer"
            className="disclaimer__link"
          >
            <ExternalLink size={14} />
            Learn about IPTV streams
          </a>
        </div>
      </div>
    </div>
  );
}

export default Disclaimer;
